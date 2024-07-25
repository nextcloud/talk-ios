//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objc extension NCRoomsManager {

    public static let statusCodeShouldIgnoreAttemptButJoinedSuccessfully = 998
    public static let statusCodeIgnoreJoinAttempt = 999

    // MARK: - Join/Leave room

    public func joinRoom(_ token: String, forCall call: Bool) {
        // Clean up joining room flag and attempts
        self.joiningRoomToken = nil
        self.joiningSessionId = nil
        self.joiningAttempts = 0
        self.joinRoomTask?.cancel()

        // Check if we try to join a room, we're still trying to leave
        if self.isLeavingRoom(withToken: token) {
            self.leavingRoomToken = nil
            self.leaveRoomTask?.cancel()
        }

        self.joinRoomHelper(token, forCall: call)
    }

    private func joinRoomHelper(_ token: String, forCall call: Bool) {
        var userInfo: [AnyHashable: Any] = [:]
        userInfo["token"] = token

        if let roomController = self.activeRooms[token] as? NCRoomController {
            if call {
                roomController.inCall = true
            } else {
                roomController.inChat = true
            }

            userInfo["roomController"] = roomController
            NotificationCenter.default.post(name: .NCRoomsManagerDidJoinRoom, object: self, userInfo: userInfo)

            return
        }

        self.joiningRoomToken = token

        self.joinRoomHelper(token, forCall: call) { sessionId, room, error, statusCode, statusReason in
            if statusCode == NCRoomsManager.statusCodeIgnoreJoinAttempt {
                // Not joining the room any more. Ignore response
                return
            } else if statusCode == NCRoomsManager.statusCodeShouldIgnoreAttemptButJoinedSuccessfully {
                // We joined the Nextcloud server successfully, but locally we are not trying to join that room anymore.
                // We need to make sure that we leave the room on the server again to not leave an active session.
                // Do a direct API call here, as the join method will check for an active NCRoomController, which we don't have

                if !self.isLeavingRoom(withToken: token) {
                    self.leavingRoomToken = token

                    let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
                    self.leaveRoomTask = NCAPIController.sharedInstance().exitRoom(token, for: activeAccount, withCompletionBlock: { _ in
                        self.leaveRoomTask = nil
                        self.leavingRoomToken = nil
                    })
                }

                return
            }

            if error == nil {
                let controller = NCRoomController()
                controller.userSessionId = sessionId
                controller.inChat = !call
                controller.inCall = call

                userInfo["roomController"] = controller

                if let room {
                    userInfo["room"] = room
                }

                // Set room as active
                self.activeRooms[token] = controller
            } else {
                if self.joiningAttempts < 3 && statusCode != 403 {
                    NCUtils.log("Error joining room, retrying. \(self.joiningAttempts)")
                    self.joiningAttempts += 1
                    self.joinRoomHelper(token, forCall: call)
                    return
                }

                // Add error to user info
                userInfo["error"] = error
                userInfo["statusCode"] = statusCode
                userInfo["errorReason"] = self.getJoinRoomErrorReason(statusCode, andReason: statusReason)

                if statusCode == 403, statusReason == "ban" {
                    userInfo["isBanned"] = true
                }

                NCUtils.log("Could not join room. Status code: \(statusCode). Error: \(error?.localizedDescription ?? "")")
            }

            NotificationCenter.default.post(name: .NCRoomsManagerDidJoinRoom, object: self, userInfo: userInfo)
        }
    }

    private func isJoiningRoom(withToken token: String) -> Bool {
        guard let joiningRoomToken = self.joiningRoomToken else { return false }

        return joiningRoomToken == token
    }

    private func isLeavingRoom(withToken token: String) -> Bool {
        guard let leavingRoomToken = self.leavingRoomToken else { return false }

        return leavingRoomToken == token
    }

    private func isJoiningRoom(withSessionId sessionId: String) -> Bool {
        guard let joiningSessionId = self.joiningSessionId else { return false }

        return joiningSessionId == sessionId
    }

    private func joinRoomHelper(_ token: String, forCall call: Bool, completionBlock: @escaping (_ sessionId: String?, _ room: NCRoom?, _ error: Error?, _ statusCode: Int, _ statusReason: String?) -> Void) {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        self.joinRoomTask = NCAPIController.sharedInstance().joinRoom(token, for: activeAccount, withCompletionBlock: { sessionId, room, error, statusCode, statusReason in
            if !self.isJoiningRoom(withToken: token) {
                // Treat a cancelled request as success, as we can't determine if the request was processed on the server or not
                if let error = error as? NSError, error.code != NSURLErrorCancelled {
                    NCUtils.log("Not joining the room any more. Ignore attempt as the join request failed anyway.")
                    completionBlock(nil, nil, nil, NCRoomsManager.statusCodeIgnoreJoinAttempt, nil)
                } else {
                    NCUtils.log("Not joining the room any more, but our join request was successful.")
                    completionBlock(nil, nil, nil, NCRoomsManager.statusCodeShouldIgnoreAttemptButJoinedSuccessfully, nil)
                }

                return
            }

            // Failed to join room in NC
            if let error {
                completionBlock(nil, nil, error, statusCode, statusReason)
                return
            }

            NCUtils.log("Joined room \(token) in NC successfully")

            guard let extSignalingController = NCSettingsController.sharedInstance().externalSignalingController(forAccountId: activeAccount.accountId)
            else {
                // Joined room in NC successfully and no external signaling server configured.
                completionBlock(sessionId, room, nil, 0, nil)
                return
            }

            NCUtils.log("Trying to join room \(token) in external signaling server...")

            // Remember the latest sessionId we're using to join a room, to be able to check when joining the external signaling server
            self.joiningSessionId = sessionId

            // TODO: For non-federated rooms, we could skip getting the settings for now
            NCAPIController.sharedInstance().getSignalingSettings(for: activeAccount, forRoom: token) { signalingSettings, _ in
                let federation = signalingSettings?.getFederationJoinDictionary()

                extSignalingController.joinRoom(token, withSessionId: sessionId, withFederation: federation) { error in
                    // If the sessionId is not the same anymore we tried to join with, we either already left again before
                    // joining the external signaling server succeeded, or we already have another join in process
                    if !self.isJoiningRoom(withToken: token) {
                        NCUtils.log("Not joining the room any more. Ignore external signaling completion block, but we joined the Nextcloud instance before.")
                        completionBlock(nil, nil, nil, NCRoomsManager.statusCodeShouldIgnoreAttemptButJoinedSuccessfully, nil)
                        return
                    }

                    if !self.isJoiningRoom(withSessionId: sessionId ?? "") {
                        NCUtils.log("Joining the same room with a different sessionId. Ignore external signaling completion block.")
                        completionBlock(nil, nil, nil, NCRoomsManager.statusCodeIgnoreJoinAttempt, nil)
                        return
                    }

                    if error == nil {
                        NCUtils.log("Joined room \(token) in external signaling server successfully.")
                        completionBlock(sessionId, room, nil, 0, nil)
                    } else {
                        NCUtils.log("Failed joining room \(token) in external signaling server.")
                        completionBlock(nil, nil, error, statusCode, statusReason)
                    }
                }
            }
        })
    }

    public func rejoinRoom(_ token: String) {
        guard let roomController = self.activeRooms[token] as? NCRoomController else { return }

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        self.joiningRoomToken = token
        self.joinRoomTask = NCAPIController.sharedInstance().joinRoom(token, for: activeAccount, withCompletionBlock: { sessionId, _, error, statusCode, _ in
            if error == nil {
                roomController.userSessionId = sessionId
                roomController.inChat = true

                if let extSignalingController = NCSettingsController.sharedInstance().externalSignalingController(forAccountId: activeAccount.accountId) {
                    NCAPIController.sharedInstance().getSignalingSettings(for: activeAccount, forRoom: token) { signalingSettings, _ in
                        let federation = signalingSettings?.getFederationJoinDictionary()

                        extSignalingController.joinRoom(token, withSessionId: sessionId, withFederation: federation, withCompletionBlock: nil)
                    }
                }
            } else {
                print("Could not re-join room. Status code: \(statusCode). Error: \(error?.localizedDescription ?? "Unknown")")
            }

            self.joiningRoomToken = nil
            self.joiningSessionId = nil
        })
    }

    public func leaveRoom(_ token: String) {
        // Check if leaving the room we are joining
        if self.isJoiningRoom(withToken: token) {
            self.joiningRoomToken = nil
            self.joiningSessionId = nil
            self.joinRoomTask?.cancel()
        }

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        // Remove room controller and exit room
        if let roomController = self.activeRooms[token] as? NCRoomController,
           !roomController.inCall, !roomController.inChat {

            self.activeRooms.removeObject(forKey: token)

            self.leavingRoomToken = token
            self.leaveRoomTask = NCAPIController.sharedInstance().exitRoom(token, for: activeAccount, withCompletionBlock: { error in
                var userInfo = [:]
                userInfo["token"] = token

                self.leaveRoomTask = nil
                self.leavingRoomToken = nil

                if let error {
                    userInfo["error"] = error
                    print("Could not exit room. Error: \(error.localizedDescription)")
                } else {
                    if let extSignalingController = NCSettingsController.sharedInstance().externalSignalingController(forAccountId: activeAccount.accountId) {
                        extSignalingController.leaveRoom(token)
                    }

                    self.checkForPendingToStartCalls()
                }

                NotificationCenter.default.post(name: .NCRoomsManagerDidLeaveRoom, object: self, userInfo: userInfo)
            })
        } else {
            self.checkForPendingToStartCalls()
        }
    }

    private func getJoinRoomErrorReason(_ statusCode: Int, andReason statusReason: String?) -> String {
        var errorReason = ""

        switch statusCode {
        case 0:
            errorReason = NSLocalizedString("No response from server", comment: "")
        case 403:
            if statusReason == "ban" {
                errorReason = NSLocalizedString("No permission to join this conversation", comment: "")
            } else {
                errorReason = NSLocalizedString("The password is wrong", comment: "")
            }
        case 404:
            errorReason = NSLocalizedString("Conversation not found", comment: "")
        case 409:
            // Currently not triggered, needs to be enabled in API with sending force=false
            errorReason = NSLocalizedString("Duplicate session", comment: "")
        case 422:
            errorReason = NSLocalizedString("Remote server is unreachable", comment: "")
        case 503:
            errorReason = NSLocalizedString("Server is currently in maintenance mode", comment: "")
        default:
            errorReason = NSLocalizedString("Unknown error occurred", comment: "")
        }

        return errorReason
    }

    // MARK: - Room

    public func roomsForAccountId(_ accountId: String, withRealm realm: RLMRealm?) -> [NCRoom] {
        let query = NSPredicate(format: "accountId = %@", accountId)
        var managedRooms: RLMResults<AnyObject>

        if let realm {
            managedRooms = NCRoom.objects(in: realm, with: query)
        } else {
            managedRooms = NCRoom.objects(with: query)
        }

        // Create an unmanaged copy of the rooms
        var unmanagedRooms: [NCRoom] = []

        for case let managedRoom as NCRoom in managedRooms {
            if managedRoom.isBreakoutRoom, managedRoom.lobbyState == .moderatorsOnly {
                continue
            }

            unmanagedRooms.append(NCRoom(value: managedRoom))
        }

        // Sort by favorites first, then by lastActivity
        unmanagedRooms.sort { first, second in
            (first.isFavorite ? 1 : 0, first.lastActivity) > (second.isFavorite ? 1 : 0, second.lastActivity)
        }

        return unmanagedRooms
    }

    public func resendOfflineMessagesWithCompletionBlock(_ block: SendOfflineMessagesCompletionBlock?) {
        // Try to send offline messages for all rooms
        self.resendOfflineMessages(forToken: nil, withCompletionBlock: block)
    }

    public func resendOfflineMessages(forToken token: String?, withCompletionBlock completionBlock: SendOfflineMessagesCompletionBlock?) {
        var query: NSPredicate

        if let token {
            query = NSPredicate(format: "isOfflineMessage = true AND token = %@", token)
        } else {
            query = NSPredicate(format: "isOfflineMessage = true")
        }

        let realm = RLMRealm.default()
        let managedTemporaryMessages = NCChatMessage.objects(with: query)
        let twelveHoursAgoTimestamp = Int(Date().timeIntervalSince1970 - (60 * 60 * 12))

        for case let offlineMessage as NCChatMessage in managedTemporaryMessages {
            // If we were unable to send a message after 12 hours, mark as failed
            if offlineMessage.timestamp < twelveHoursAgoTimestamp {
                try? realm.transaction {
                    offlineMessage.isOfflineMessage = false
                    offlineMessage.sendingFailed = true
                }

                var userInfo: [AnyHashable: Any] = [:]
                userInfo["message"] = offlineMessage
                userInfo["isOfflineMessage"] = false

                if offlineMessage.referenceId != nil {
                    userInfo["referenceId"] = offlineMessage.referenceId
                }

                // Inform the chatViewController about this change
                NotificationCenter.default.post(name: .NCChatControllerDidSendChatMessage, object: self, userInfo: userInfo)
            } else {
                if let room = NCDatabaseManager.sharedInstance().room(withToken: offlineMessage.token, forAccountId: offlineMessage.accountId),
                   let chatController = NCChatController(for: room) {
                    chatController.send(offlineMessage)
                }
            }
        }

        completionBlock?()
    }

    // MARK: - Federation invitations

    public func checkUpdateNeededForPendingFederationInvitations() {
        guard NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityFederationV1) else { return }

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let tenMinutesAgo = Int(Date().timeIntervalSince1970 - (10 * 60))

        if activeAccount.lastPendingFederationInvitationFetch == 0 || activeAccount.lastPendingFederationInvitationFetch < tenMinutesAgo {
            self.updatePendingFederationInvitations()
        }
    }

    public func updatePendingFederationInvitations() {
        guard NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityFederationV1) else { return }

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        NCAPIController.sharedInstance().getFederationInvitations(for: activeAccount.accountId) { invitations in
            guard let invitations else { return }
            let pendingInvitations = invitations.filter { $0.invitationState != .accepted }

            if activeAccount.pendingFederationInvitations != pendingInvitations.count {
                NCDatabaseManager.sharedInstance().setPendingFederationInvitationForAccountId(activeAccount.accountId, with: pendingInvitations.count)
            }
        }
    }
}
