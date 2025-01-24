//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objc extension NCAPIController {

    // MARK: - Rooms Controller

    public func getRooms(forAccount account: TalkAccount, updateStatus: Bool, modifiedSince: Int, completionBlock: @escaping (_ rooms: [[String: AnyObject]]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else { return }

        var urlString = self.getRequestURL(forConversationEndpoint: "room", for: account)
        let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId)

        let parameters: [String: Any] = [
            "noStatusUpdate": !updateStatus,
            "modifiedSince": modifiedSince
        ]

        // Since we are using "modifiedSince" only in background fetches
        // we will request including user status only when getting the complete room list
        if serverCapabilities?.userStatus == true, modifiedSince == 0 {
            urlString = urlString.appending("?includeStatus=true")
        }

        apiSessionManager.getOcs(urlString, account: account, parameters: parameters) { ocsResponse, ocsError in
            if let response = ocsResponse?.task?.response as? HTTPURLResponse {
                var numberOfPendingInvitations = 0

                // If the header is not present, there are no pending invites
                if let federationInvitesString = response.allHeaderFields["x-nextcloud-talk-federation-invites"] as? String {
                    numberOfPendingInvitations = Int(federationInvitesString) ?? 0
                }

                if account.pendingFederationInvitations != numberOfPendingInvitations {
                    NCDatabaseManager.sharedInstance().setPendingFederationInvitationForAccountId(account.accountId, with: numberOfPendingInvitations)
                }
            }

            // TODO: Move away from generic dictionary return type
            // let rooms = ocs?.dataArrayDict.compactMap { NCRoom(dictionary: $0, andAccountId: account.accountId) }
            completionBlock(ocsResponse?.dataArrayDict, ocsError?.error)
        }
    }

    public func getRoom(forAccount account: TalkAccount, withToken token: String, completionBlock: @escaping (_ room: [String: AnyObject]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)", for: account)

        apiSessionManager.getOcs(urlString, account: account) { ocsResponse, ocsError in
            completionBlock(ocsResponse?.dataDict, ocsError?.error)
        }
    }

    public func getNoteToSelfRoom(forAccount account: TalkAccount, completionBlock: @escaping (_ room: [String: AnyObject]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/note-to-self", for: account)

        apiSessionManager.getOcs(urlString, account: account) { ocsResponse, ocsError in
            completionBlock(ocsResponse?.dataDict, ocsError?.error)
        }
    }

    public func getListableRooms(forAccount account: TalkAccount, withSerachTerm searchTerm: String?, completionBlock: @escaping (_ rooms: [NCRoom]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "listed-room", for: account)
        var parameters: [String: Any] = [:]

        if let searchTerm, !searchTerm.isEmpty {
            parameters["searchTerm"] = searchTerm
        }

        apiSessionManager.getOcs(urlString, account: account, parameters: parameters) { ocsResponse, ocsError in
            let rooms = ocsResponse?.dataArrayDict?.compactMap { NCRoom(dictionary: $0, andAccountId: account.accountId) }
            completionBlock(rooms, ocsError?.error)
        }
    }

    public func createRoom(forAccount account: TalkAccount, withInvite invite: String?, ofType roomType: NCRoomType, andName roomName: String?, completionBlock: @escaping (_ room: NCRoom?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room", for: account)
        var parameters: [String: Any] = ["roomType": roomType.rawValue]

        if let invite, !invite.isEmpty {
            parameters["invite"] = invite
        }

        if let roomName, !roomName.isEmpty {
            parameters["roomName"] = roomName
        }

        apiSessionManager.postOcs(urlString, account: account, parameters: parameters) { ocsResponse, ocsError in
            let room = NCRoom(dictionary: ocsResponse?.dataDict, andAccountId: account.accountId)
            completionBlock(room, ocsError?.error)
        }
    }

    public func renameRoom(_ token: String, forAccount account: TalkAccount, withName roomName: String, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)", for: account)
        let parameters: [String: String] = ["roomName": roomName]

        apiSessionManager.putOcs(urlString, account: account, parameters: parameters) { _, ocsError in
            completionBlock(ocsError?.error)
        }
    }

    public func setRoomDescription(_ description: String?, forRoom token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/description", for: account)
        let parameters: [String: String] = ["description": description ?? ""]

        apiSessionManager.putOcs(urlString, account: account, parameters: parameters) { _, ocsError in
            completionBlock(ocsError?.error)
        }
    }

    public func setMentionPermissions(_ permissions: NCRoomMentionPermissions, forRoom token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/mention-permissions", for: account)
        let parameters: [String: Int] = ["mentionPermissions": permissions.rawValue]

        apiSessionManager.putOcs(urlString, account: account, parameters: parameters) { _, ocsError in
            completionBlock(ocsError?.error)
        }
    }

    public func makeRoomPublic(_ token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/public", for: account)

        apiSessionManager.postOcs(urlString, account: account) { _, ocsError in
            completionBlock(ocsError?.error)
        }
    }

    public func makeRoomPrivate(_ token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/public", for: account)

        apiSessionManager.deleteOcs(urlString, account: account) { _, ocsError in
            completionBlock(ocsError?.error)
        }
    }

    public func deleteRoom(_ token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)", for: account)

        apiSessionManager.deleteOcs(urlString, account: account) { _, ocsError in
            completionBlock(ocsError?.error)
        }
    }

    public func setPassword(_ password: String, forRoom token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?, _ errorDescription: String?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/password", for: account)
        let parameters: [String: String] = ["password": password]

        apiSessionManager.putOcs(urlString, account: account, parameters: parameters) { _, ocsError in
            // When password does not match the password-policy, we receive a 400
            if ocsError?.responseStatusCode == 400 {
                // message is already translated server-side
                completionBlock(ocsError?.error, ocsError?.errorMessage)
            } else {
                completionBlock(ocsError?.error, nil)
            }
        }
    }

    public func addRoomToFavorites(_ token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/favorite", for: account)

        apiSessionManager.postOcs(urlString, account: account) { _, ocsError in
            completionBlock(ocsError?.error)
        }
    }

    public func removeRoomFromFavorites(_ token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/favorite", for: account)

        apiSessionManager.deleteOcs(urlString, account: account) { _, ocsError in
            completionBlock(ocsError?.error)
        }
    }

    // MARK: - Federation

    public func acceptFederationInvitation(for accountId: String, with invitationId: Int, completionBlock: @escaping (_ success: Bool) -> Void) {
        let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId)!
        let apiVersion = self.federationAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "federation/invitation/\(invitationId)", withAPIVersion: apiVersion, for: account)

        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else {
            completionBlock(false)
            return
        }

        apiSessionManager.postOcs(urlString, account: account) { _, error in
            completionBlock(error == nil)
        }
    }

    public func rejectFederationInvitation(for accountId: String, with invitationId: Int, completionBlock: @escaping (_ success: Bool) -> Void) {
        let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId)!
        let apiVersion = self.federationAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "federation/invitation/\(invitationId)", withAPIVersion: apiVersion, for: account)

        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else {
            completionBlock(false)
            return
        }

        apiSessionManager.deleteOcs(urlString, account: account) { _, error in
            completionBlock(error == nil)
        }
    }

    public func getFederationInvitations(for accountId: String, completionBlock: @escaping (_ invitations: [FederationInvitation]?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: accountId) as? NCAPISessionManager,
              let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId)
        else {
            completionBlock(nil)
            return
        }

        let apiVersion = self.federationAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "federation/invitation", withAPIVersion: apiVersion, for: account)

        apiSessionManager.getOcs(urlString, account: account) { ocs, _ in
            let invitations = ocs?.dataArrayDict?.map { FederationInvitation(dictionary: $0, for: accountId) }
            completionBlock(invitations)
        }
    }

    // MARK: - Room capabilities

    public func getRoomCapabilities(for accountId: String, token: String, completionBlock: @escaping (_ roomCapabilities: [String: AnyObject]?, _ proxyHash: String?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else {
            completionBlock(nil, nil)
            return
        }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/capabilities", for: account)

        apiSessionManager.getOcs(urlString, account: account) { ocs, _ in
            if let data = ocs?.dataDict,
               let response = ocs?.task?.response,
               let headers = self.getResponseHeaders(response) {

                // Need to use lowercase name in swift
                if let headerProxyHash = headers["x-nextcloud-talk-proxy-hash"] as? String {
                    completionBlock(data, headerProxyHash)
                } else {
                    completionBlock(data, nil)
                }

            } else {
                completionBlock(nil, nil)
            }
        }
    }

    // MARK: - Signaling

    @discardableResult
    public func getSignalingSettings(for account: TalkAccount, forRoom roomToken: String?, completionBlock: @escaping (_ signalingSettings: SignalingSettings?, _ error: (any Error)?) -> Void) -> URLSessionDataTask? {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else {
            completionBlock(nil, nil)
            return nil
        }

        let apiVersion = self.signalingAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "signaling/settings", withAPIVersion: apiVersion, for: account)

        var parameters: [String: Any]?

        if let roomToken, let encodedToken = roomToken.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) {
            parameters = [
                "token": encodedToken
            ]
        }

        return apiSessionManager.getOcs(urlString, account: account, parameters: parameters) { ocsResponse, ocsError in
            completionBlock(SignalingSettings(dictionary: ocsResponse?.dataDict), ocsError?.error)
        }
    }

    // MARK: - Mentions

    public func getMentionSuggestions(for accountId: String, in roomToken: String, with searchString: String, completionBlock: @escaping (_ mentions: [MentionSuggestion]?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = roomToken.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId)
        else {
            completionBlock(nil)
            return
        }

        let apiVersion = self.chatAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/mentions", withAPIVersion: apiVersion, for: account)

        let parameters: [String: Any] = [
            "limit": 20,
            "search": searchString,
            "includeStatus": serverCapabilities.userStatus
        ]

        apiSessionManager.getOcs(urlString, account: account, parameters: parameters) { ocs, _ in
            let mentions = ocs?.dataArrayDict?.map { MentionSuggestion(dictionary: $0) }
            completionBlock(mentions)
        }
    }

    // MARK: - Ban

    public func banActor(for accountId: String, in roomToken: String, with actorType: String, with actorId: String, with internalNote: String?, completionBlock: @escaping (_ success: Bool) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let encodedToken = roomToken.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else {
            completionBlock(false)
            return
        }

        let apiVersion = self.banAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "ban/\(encodedToken)", withAPIVersion: apiVersion, for: account)

        var parameters: [String: Any] = [
            "actorType": actorType,
            "actorId": actorId
        ]

        if let internalNote, !internalNote.isEmpty {
            parameters["internalNote"] = internalNote
        }

        apiSessionManager.post(urlString, parameters: parameters, progress: nil) { _, _ in
            completionBlock(true)
        } failure: { _, _ in
            completionBlock(false)
        }
    }

    public func listBans(for accountId: String, in roomToken: String, completionBlock: @escaping (_ bannedActors: [BannedActor]?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let encodedToken = roomToken.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else {
            completionBlock(nil)
            return
        }

        let apiVersion = self.banAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "ban/\(encodedToken)", withAPIVersion: apiVersion, for: account)

        apiSessionManager.getOcs(urlString, account: account) { ocs, _ in
            let actorBans = ocs?.dataArrayDict?.map { BannedActor(dictionary: $0) }
            completionBlock(actorBans)
        }
    }

    public func unbanActor(for accountId: String, in roomToken: String, with banId: Int, completionBlock: @escaping (_ success: Bool) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let encodedToken = roomToken.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else {
            completionBlock(false)
            return
        }

        let apiVersion = self.banAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "ban/\(encodedToken)/\(banId)", withAPIVersion: apiVersion, for: account)

        apiSessionManager.delete(urlString, parameters: nil) { _, _ in
            completionBlock(true)
        } failure: { _, _ in
            completionBlock(false)
        }
    }

    // MARK: - AI

    public enum SummarizeChatStatus: Int {
        case success = 0
        case noMessagesFound
        case noAiProvider
        case failed
    }

    @nonobjc
    public func summarizeChat(forAccountId accountId: String, inRoom roomToken: String, fromMessageId messageId: Int, completionBlock: @escaping (_ status: SummarizeChatStatus, _ taskId: Int?, _ nextOffset: Int?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = roomToken.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else {
            completionBlock(.failed, nil, nil)
            return
        }

        let apiVersion = self.chatAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/summarize", withAPIVersion: apiVersion, for: account)

        let parameters: [String: Int] = [
            "fromMessageId": messageId
        ]

        apiSessionManager.postOcs(urlString, account: account, parameters: parameters) { ocsResponse, ocsError in
            if ocsResponse?.responseStatusCode == 204 {
                completionBlock(.noMessagesFound, nil, nil)
                return
            }

            if ocsError?.responseStatusCode == 500, let error = ocsError?.dataDict?["error"] as? String, error == "ai-no-provider" {
                completionBlock(.noAiProvider, nil, nil)
                return
            }

            guard let dict = ocsResponse?.dataDict as? [String: Int] else {
                completionBlock(.failed, nil, nil)
                return
            }

            completionBlock(.success, dict["taskId"], dict["nextOffset"])
        }
    }

    public enum AiTaskStatus: Int {
        case unknown = 0
        case scheduled = 1
        case running = 2
        case successful = 3
        case failed = 4
        case cancelled = 5

        init(stringResponse: String) {
            switch stringResponse {
            case "STATUS_SCHEDULED": self = .scheduled
            case "STATUS_RUNNING": self = .running
            case "STATUS_SUCCESSFUL": self = .successful
            case "STATUS_FAILED": self = .failed
            case "STATUS_CANCELLED": self = .cancelled
            default: self = .unknown
            }
        }
    }

    @nonobjc
    public func getAiTaskById(for accountId: String, withTaskId taskId: Int, completionBlock: @escaping (_ status: AiTaskStatus, _ output: String?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else {
            completionBlock(.failed, nil)
            return
        }

        let urlString = "\(account.server)/ocs/v2.php/taskprocessing/task/\(taskId)"

        apiSessionManager.getOcs(urlString, account: account) { ocsResponse, ocsError in
            guard ocsError == nil,
                  let taskDict = ocsResponse?.dataDict?["task"] as? [String: Any],
                  let status = taskDict["status"] as? String
            else {
                completionBlock(.failed, nil)
                return
            }

            let outputDict = taskDict["output"] as? [String: Any]
            completionBlock(AiTaskStatus(stringResponse: status), outputDict?["output"] as? String)
        }
    }

    // MARK: - Out-of-office

    public func getCurrentUserAbsence(forAccountId accountId: String, forUserId userId: String, completionBlock: @escaping (_ absenceData: CurrentUserAbsence?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else {
            completionBlock(nil)
            return
        }

        let urlString = "\(account.server)/ocs/v2.php/apps/dav/api/v1/outOfOffice/\(encodedUserId)/now"

        apiSessionManager.getOcs(urlString, account: account) { ocsResponse, _ in
            guard let dataDict = ocsResponse?.dataDict else {
                completionBlock(nil)
                return
            }
            completionBlock(CurrentUserAbsence(dictionary: dataDict))
        }
    }

    @nonobjc
    public func getUserAbsence(forAccountId accountId: String, forUserId userId: String, completionBlock: @escaping (_ absenceData: UserAbsence?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else {
            completionBlock(nil)
            return
        }

        let urlString = "\(account.server)/ocs/v2.php/apps/dav/api/v1/outOfOffice/\(encodedUserId)"

        apiSessionManager.getOcs(urlString, account: account) { ocsResponse, _ in
            guard let dataDict = ocsResponse?.dataDict else {
                completionBlock(nil)
                return
            }
            completionBlock(UserAbsence(dictionary: dataDict))
        }
    }

    public func clearUserAbsence(forAccountId accountId: String, forUserId userId: String, completionBlock: @escaping (_ success: Bool) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else {
            completionBlock(false)
            return
        }

        let urlString = "\(account.server)/ocs/v2.php/apps/dav/api/v1/outOfOffice/\(encodedUserId)"

        apiSessionManager.deleteOcs(urlString, account: account) { _, ocsError in
            completionBlock(ocsError == nil)
        }
    }

    @nonobjc
    public func setUserAbsence(forAccountId accountId: String, forUserId userId: String, withAbsence absenceData: UserAbsence, completionBlock: @escaping (_ success: Bool) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let absenceDictionary = absenceData.asDictionary()
        else {
            completionBlock(false)
            return
        }

        let urlString = "\(account.server)/ocs/v2.php/apps/dav/api/v1/outOfOffice/\(encodedUserId)"

        apiSessionManager.postOcs(urlString, account: account, parameters: absenceDictionary) { _, ocsError in
            completionBlock(ocsError == nil)
        }
    }

    // MARK: - Notifications

    // Needs to be of type Int to be usable from objc
    @objc public enum CallNotificationState: Int {
        case unknown, stillCurrent, roomNotFound, missedCall, participantJoined
    }

    @discardableResult
    public func getCallNotificationState(for account: TalkAccount, forRoom roomToken: String, completionBlock: @escaping (_ callNotificationState: CallNotificationState) -> Void) -> URLSessionDataTask? {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = roomToken.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else {
            completionBlock(.unknown)
            return nil
        }

        let apiVersion = self.callAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "call/\(encodedToken)/notification-state", withAPIVersion: apiVersion, for: account)

        return apiSessionManager.getOcs(urlString, account: account) { ocsResponse, ocsError in
            if ocsResponse?.responseStatusCode == 200 {
                completionBlock(.stillCurrent)
            } else if ocsResponse?.responseStatusCode == 201 {
                completionBlock(.missedCall)
            } else if ocsError?.responseStatusCode == 403 {
                completionBlock(.roomNotFound)
            } else if ocsError?.responseStatusCode == 404 {
                completionBlock(.participantJoined)
            } else {
                completionBlock(.unknown)
            }
        }
    }

    // MARK: - Archived conversations

    public func archiveRoom(_ token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ success: Bool) -> Void) {
        guard let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else {
            completionBlock(false)
            return
        }

        let apiVersion = self.conversationAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "room/\(encodedToken)/archive", withAPIVersion: apiVersion, for: account)

        apiSessionManager.postOcs(urlString, account: account) { _, error in
            completionBlock(error == nil)
        }
    }

    public func unarchiveRoom(_ token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ success: Bool) -> Void) {
        guard let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else {
            completionBlock(false)
            return
        }

        let apiVersion = self.conversationAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "room/\(encodedToken)/archive", withAPIVersion: apiVersion, for: account)

        apiSessionManager.deleteOcs(urlString, account: account) { _, error in
            completionBlock(error == nil)
        }
    }

    // MARK: - Push notification test

    public func testPushnotifications(forAccount account: TalkAccount, completionBlock: @escaping (_ result: String?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else {
            completionBlock(nil)
            return
        }

        let urlString = "\(account.server)/ocs/v2.php/apps/notifications/api/v3/test/self"

        apiSessionManager.postOcs(urlString, account: account) { ocsResponse, _ in
            let message = ocsResponse?.dataDict?["message"] as? String
            completionBlock(message)
        }
    }
}
