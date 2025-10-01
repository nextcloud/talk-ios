//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import NextcloudKit

@objc extension NCAPIController {

    enum ApiControllerError: Error {
        case preconditionError
        case unexpectedOcsResponse
    }

    // MARK: - Rooms Controller

    @discardableResult
    public func joinRoom(_ token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ sessionId: String?, _ room: NCRoom?, _ error: Error?, _ statusCode: Int, _ statusReason: String?) -> Void) -> URLSessionTask? {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return nil }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/participants/active", for: account)

        return apiSessionManager.postOcs(urlString, account: account) { ocsResponse, ocsError in
            if let ocsError {
                completionBlock(nil, nil, ocsError.error, ocsError.responseStatusCode, ocsError.errorKey)
                return
            }

            if let response = ocsResponse?.task?.response as? HTTPURLResponse {
                self.checkProxyResponseHeaders(response.allHeaderFields, for: account, forRoom: token)
            }

            var room: NCRoom?

            // Room object is returned only since Talk 11
            if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityListableRooms) {
                room = NCRoom(dictionary: ocsResponse?.dataDict, andAccountId: account.accountId)

                // In case there's no token, or a non-matching token, don't return
                if room?.token != token {
                    room = nil
                }
            }

            completionBlock(ocsResponse?.dataDict?["sessionId"] as? String, room, nil, 0, nil)
        }
    }

    @discardableResult
    public func exitRoom(_ token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) -> URLSessionTask? {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return nil }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/participants/active", for: account)

        return apiSessionManager.deleteOcs(urlString, account: account) { _, ocsError in
            if let ocsError {
                completionBlock(ocsError.error)
                return
            }

            completionBlock(nil)
        }
    }

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

    @MainActor
    @discardableResult
    public func getRoom(forAccount account: TalkAccount, withToken token: String) async throws -> NCRoom? {
        return try await withCheckedThrowingContinuation { continuation in
            self.getRoom(forAccount: account, withToken: token) { room, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: NCRoom(dictionary: room, andAccountId: account.accountId))
                }
            }
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

    public func createRoom(forAccount account: TalkAccount, withParameters parameters: [String: Any], completionBlock: @escaping (_ room: NCRoom?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room", for: account)

        apiSessionManager.postOcs(urlString, account: account, parameters: parameters) { ocsResponse, ocsError in
            let room = NCRoom(dictionary: ocsResponse?.dataDict, andAccountId: account.accountId)
            completionBlock(room, ocsError?.error)
        }
    }

    public func createRoom(forAccount account: TalkAccount, withInvite invite: String?, ofType roomType: NCRoomType, andName roomName: String?, completionBlock: @escaping (_ room: NCRoom?, _ error: Error?) -> Void) {
        var parameters: [String: Any] = ["roomType": roomType.rawValue]

        if let invite, !invite.isEmpty {
            parameters["invite"] = invite
        }

        if let roomName, !roomName.isEmpty {
            parameters["roomName"] = roomName
        }

        self.createRoom(forAccount: account, withParameters: parameters, completionBlock: completionBlock)
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

    public func unbindRoomFromObject(_ token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/object", for: account)

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

    @MainActor
    public func setImportantState(enabled: Bool, forRoom token: String, forAccount account: TalkAccount) async throws -> NCRoom? {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return nil }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/important", for: account)
        var ocsResponse: OcsResponse

        if enabled {
            ocsResponse = try await apiSessionManager.postOcs(urlString, account: account)
        } else {
            ocsResponse = try await apiSessionManager.deleteOcs(urlString, account: account)
        }

        return NCRoom(dictionary: ocsResponse.dataDict, andAccountId: account.accountId)
    }

    @MainActor
    public func setSensitiveState(enabled: Bool, forRoom token: String, forAccount account: TalkAccount) async throws -> NCRoom? {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return nil }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/sensitive", for: account)
        var ocsResponse: OcsResponse

        if enabled {
            ocsResponse = try await apiSessionManager.postOcs(urlString, account: account)
        } else {
            ocsResponse = try await apiSessionManager.deleteOcs(urlString, account: account)
        }

        return NCRoom(dictionary: ocsResponse.dataDict, andAccountId: account.accountId)
    }

    @MainActor
    public func setNotificationLevel(level: NCRoomNotificationLevel, forRoom token: String, forAccount account: TalkAccount) async -> Bool {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return false }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/notify", for: account)
        let parameters: [String: Int] = ["level": level.rawValue]

        let ocsResponse = try? await apiSessionManager.postOcs(urlString, account: account, parameters: parameters)

        // Older endpoints don't return the room object
        // return NCRoom(dictionary: ocsResponse.dataDict, andAccountId: account.accountId)
        return (ocsResponse != nil)
    }

    @MainActor
    public func setCallNotificationLevel(enabled: Bool, forRoom token: String, forAccount account: TalkAccount) async -> Bool {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return false }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/notify-calls", for: account)
        let parameters: [String: Bool] = ["level": enabled]

        let ocsResponse = try? await apiSessionManager.postOcs(urlString, account: account, parameters: parameters)

        // Older endpoints don't return the room object
        // return NCRoom(dictionary: ocsResponse.dataDict, andAccountId: account.accountId)
        return (ocsResponse != nil)
    }

    @MainActor
    @discardableResult
    public func setReadOnlyState(state: NCRoomReadOnlyState, forRoom token: String, forAccount account: TalkAccount) async throws -> OcsResponse {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/read-only", for: account)
        let parameters: [String: Int] = ["state": state.rawValue]

        return try await apiSessionManager.putOcs(urlString, account: account, parameters: parameters)
    }

    @MainActor
    @discardableResult
    public func setLobbyState(state: NCRoomLobbyState, withTimer timer: Int, forRoom token: String, forAccount account: TalkAccount) async throws -> OcsResponse {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let endpoint = self.conversationAPIVersion(for: account) >= APIv4 ? "room/\(encodedToken)/webinar/lobby" : "room/\(encodedToken)/webinary/lobby"
        let urlString = self.getRequestURL(forConversationEndpoint: endpoint, for: account)
        var parameters: [String: Int] = ["state": state.rawValue]

        if timer > 0 {
            parameters["timer"] = timer
        }

        return try await apiSessionManager.putOcs(urlString, account: account, parameters: parameters)
    }

    @MainActor
    @discardableResult
    public func setSIPState(state: NCRoomSIPState, forRoom token: String, forAccount account: TalkAccount) async throws -> OcsResponse {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/webinar/sip", for: account)
        let parameters: [String: Int] = ["state": state.rawValue]

        return try await apiSessionManager.putOcs(urlString, account: account, parameters: parameters)
    }

    @MainActor
    @discardableResult
    public func setListableScope(scope: NCRoomListableScope, forRoom token: String, forAccount account: TalkAccount) async throws -> OcsResponse {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/listable", for: account)
        let parameters: [String: Int] = ["scope": scope.rawValue]

        return try await apiSessionManager.putOcs(urlString, account: account, parameters: parameters)
    }

    @MainActor
    @discardableResult
    public func setMessageExpiration(messageExpiration: NCMessageExpiration, forRoom token: String, forAccount account: TalkAccount) async throws -> OcsResponse {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/message-expiration", for: account)
        let parameters: [String: Int] = ["seconds": messageExpiration.rawValue]

        return try await apiSessionManager.postOcs(urlString, account: account, parameters: parameters)
    }

    // MARK: - Participants

    @MainActor
    @discardableResult
    public func getParticipants(forRoom token: String, forAccount account: TalkAccount) async throws -> [NCRoomParticipant] {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        var urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/participants", for: account)
        let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId)

        if serverCapabilities?.userStatus == true {
            urlString += "?includeStatus=true"
        }

        let response = try await apiSessionManager.getOcs(urlString, account: account)
        guard let dataArrayDict = response.dataArrayDict else { throw ApiControllerError.unexpectedOcsResponse }

        let participants = dataArrayDict.compactMap { NCRoomParticipant(dictionary: $0) }

        return participants.sortedParticipants()
    }

    @MainActor
    @discardableResult
    public func addParticipant(_ participant: String, ofType type: String?, toRoom token: String, forAccount account: TalkAccount) async throws -> OcsResponse {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/participants", for: account)
        var parameters: [String: String] = ["newParticipant": participant]

        if let type {
            parameters["source"] = type
        }

        return try await apiSessionManager.postOcs(urlString, account: account, parameters: parameters)
    }

    @MainActor
    @discardableResult
    public func removeAttendee(_ attendeeId: Int, forRoom token: String, forAccount account: TalkAccount) async throws -> OcsResponse {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/attendees", for: account)
        let parameters: [String: Int] = ["attendeeId": attendeeId]

        return try await apiSessionManager.deleteOcs(urlString, account: account, parameters: parameters)
    }

    @MainActor
    @discardableResult
    public func removeParticipant(_ participant: String, forRoom token: String, forAccount account: TalkAccount) async throws -> OcsResponse {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/participants", for: account)
        let parameters: [String: String] = ["participant": participant]

        return try await apiSessionManager.deleteOcs(urlString, account: account, parameters: parameters)
    }

    @MainActor
    @discardableResult
    public func removeGuest(_ guest: String, forRoom token: String, forAccount account: TalkAccount) async throws -> OcsResponse {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/guests", for: account)
        let parameters: [String: String] = ["participant": guest]

        return try await apiSessionManager.deleteOcs(urlString, account: account, parameters: parameters)
    }

    @MainActor
    @discardableResult
    public func removeSelf(fromRoom token: String, forAccount account: TalkAccount) async throws -> OcsResponse {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/participants/self", for: account)

        return try await apiSessionManager.deleteOcs(urlString, account: account)
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

    public enum SetUserAbsenceResponse: Int {
        case unknownError = 0
        case success = 1
        case statusLengthError = 2
        case firstDayError = 3

        init(errorKey: String?) {
            switch errorKey {
            case nil: self = .success
            case "statusLength": self = .statusLengthError
            case "firstDay": self = .firstDayError
            default: self = .unknownError
            }
        }
    }

    @nonobjc
    public func setUserAbsence(forAccountId accountId: String, forUserId userId: String, withAbsence absenceData: UserAbsence, completionBlock: @escaping (_ response: SetUserAbsenceResponse) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let absenceDictionary = absenceData.asDictionary()
        else {
            completionBlock(.unknownError)
            return
        }

        let urlString = "\(account.server)/ocs/v2.php/apps/dav/api/v1/outOfOffice/\(encodedUserId)"

        apiSessionManager.postOcs(urlString, account: account, parameters: absenceDictionary) { _, ocsError in
            completionBlock(SetUserAbsenceResponse(errorKey: ocsError?.errorKey))
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

    // MARK: - Upcoming events

    @nonobjc
    func upcomingEvents(_ room: NCRoom, forAccount account: TalkAccount, completionBlock: @escaping (_ events: [CalendarEvent]) -> Void) {
        guard let encodedRoomLink = room.linkURL?.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else {
            completionBlock([])
            return
        }

        let urlString = "\(account.server)/ocs/v2.php/apps/dav/api/v1/events/upcoming?location=\(encodedRoomLink)"

        apiSessionManager.getOcs(urlString, account: account) { ocsResponse, error in
            if error == nil, let events = ocsResponse?.dataDict?["events"] as? [[String: Any]] {
                let calendarEvents = events.map { CalendarEvent(dictionary: $0) }
                completionBlock(calendarEvents)
            } else {
                completionBlock([])
            }
        }
    }

    // MARK: - Groups & Teams

    func getUserGroups(forAccount account: TalkAccount, completionBlock: @escaping (_ groupIds: [String]?, _ error: Error?) -> Void) {
        guard let encodedUserId = account.userId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else {
            completionBlock(nil, NSError(domain: "", code: 0, userInfo: nil))
            return
        }

        let urlString = "\(account.server)/ocs/v2.php/cloud/users/\(encodedUserId)/groups"

        apiSessionManager.getOcs(urlString, account: account) { ocsResponse, ocsError in
            if ocsError?.error == nil, let groupdIds = ocsResponse?.dataDict?["groups"] as? [String] {
                completionBlock(groupdIds, nil)
            } else {
                completionBlock(nil, ocsError?.error)
            }
        }
    }

    func getUserTeams(forAccount account: TalkAccount, completionBlock: @escaping (_ teamIds: [String]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else {
            completionBlock(nil, NSError(domain: "", code: 0, userInfo: nil))
            return
        }

        let urlString = "\(account.server)/ocs/v2.php/apps/circles/probecircles"

        apiSessionManager.getOcs(urlString, account: account) { ocsResponse, ocsError in
            if ocsError?.error == nil, let teamsDicts = ocsResponse?.dataArrayDict {
                let teamIds = teamsDicts.compactMap { $0["id"] as? String }
                completionBlock(teamIds, nil)
            } else {
                completionBlock(nil, ocsError?.error)
            }
        }
    }

    // MARK: - File operations

    func getFileById(forAccount account: TalkAccount, withFileId fileId: String, completionBlock: @escaping (_ file: NKFile?, _ error: NKError?) -> Void) {
        self.setupNCCommunication(for: account)

        let body = """
            <?xml version=\"1.0\" encoding=\"UTF-8\"?>\
            <d:searchrequest xmlns:d=\"DAV:\" xmlns:oc=\"http://nextcloud.com/ns\">\
            <d:basicsearch>\
            <d:select>\
                <d:prop>\
                    <d:displayname />\
                    <d:getcontenttype />\
                    <d:resourcetype />\
                    <d:getcontentlength />\
                    <d:getlastmodified />\
                    <d:creationdate />\
                    <d:getetag />\
                    <d:quota-used-bytes />\
                    <d:quota-available-bytes />\
                    <oc:fileid xmlns:oc=\"http://owncloud.org/ns\" />\
                    <oc:permissions xmlns:oc=\"http://owncloud.org/ns\" />\
                    <oc:id xmlns:oc=\"http://owncloud.org/ns\" />\
                    <oc:size xmlns:oc=\"http://owncloud.org/ns\" />\
                    <oc:favorite xmlns:oc=\"http://owncloud.org/ns\" />\
                </d:prop>\
            </d:select>\
            <d:from>\
                <d:scope>\
                    <d:href>/files/%@</d:href>\
                    <d:depth>infinity</d:depth>\
                </d:scope>\
            </d:from>\
            <d:where>\
                <d:eq>\
                    <d:prop>\
                        <oc:fileid xmlns:oc=\"http://owncloud.org/ns\" />\
                    </d:prop>\
                    <d:literal>%@</d:literal>\
                </d:eq>\
            </d:where>\
            <d:orderby />\
            </d:basicsearch>\
            </d:searchrequest>
            """

        let bodyRequest = String(format: body, account.userId, fileId)
        let options = NKRequestOptions(timeout: 60, queue: .main)

        NextcloudKit.shared.searchBodyRequest(serverUrl: account.server, requestBody: bodyRequest, showHiddenFiles: true, options: options) { _, files, _, error in
            completionBlock(files.first, error)
        }
    }

    // MARK: - Profile

    @nonobjc
    func getUserProfile(forUserId userId: String, forAccount account: TalkAccount, completionBlock: @escaping (_ info: ProfileInfo?) -> Void) {
        guard let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else {
            completionBlock(nil)
            return
        }

        let urlString = "\(account.server)/ocs/v2.php/profile/\(encodedUserId)"

        apiSessionManager.getOcs(urlString, account: account) { ocsResponse, error in
            // Note: HTTP 405 -> Server does not support the endpoint
            guard let dataDict = ocsResponse?.dataDict else {
                completionBlock(nil)
                return
            }

            completionBlock(ProfileInfo(dictionary: dataDict))
        }
    }

    // MARK: - Threads

    @nonobjc
    public func getThreads(for accountId: String, in roomToken: String, withLimit limit: Int = 50, completionBlock: @escaping (_ threads: [NCThread]?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = roomToken.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else {
            completionBlock(nil)
            return
        }

        let apiVersion = self.chatAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/threads/recent", withAPIVersion: apiVersion, for: account)

        let parameters: [String: Any] = [
            "limit": limit
        ]

        apiSessionManager.getOcs(urlString, account: account, parameters: parameters) { ocs, _ in
            if let threads = ocs?.dataArrayDict?.map({ NCThread(dictionary: $0, andAccountId: accountId) }), !threads.isEmpty {
                NCThread.storeOrUpdateThreads(threads)
                completionBlock(threads)
            } else {
                completionBlock(nil)
            }
        }
    }

    public func getSubscribedThreads(for accountId: String, withLimit limit: Int = 100, andOffset offset: Int = 0, completionBlock: @escaping (_ threads: [NCThread]?, _ error: Error?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else {
            completionBlock(nil, NSError(domain: "", code: 0, userInfo: nil))
            return
        }

        let apiVersion = self.chatAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "chat/subscribed-threads", withAPIVersion: apiVersion, for: account)

        let parameters: [String: Any] = [
            "limit": limit,
            "offfset": offset
        ]

        apiSessionManager.getOcs(urlString, account: account, parameters: parameters) { ocsResponse, ocsError in
            if let error = ocsError?.error {
                completionBlock(nil, error)
            } else if let threads = ocsResponse?.dataArrayDict?.map({ NCThread(dictionary: $0, andAccountId: accountId) }) {
                NCThread.storeOrUpdateThreads(threads)

                NCDatabaseManager.sharedInstance().updateHasThreads(forAccountId: accountId, with: !threads.isEmpty)
                NCDatabaseManager.sharedInstance().updateThreadsLastCheckTimestamp(forAccountId: accountId, with: Int(Date().timeIntervalSince1970))

                let userInfo: [AnyHashable: Any] = [
                    "threads": threads,
                    "accountId" : accountId
                ]
                NotificationCenter.default.post(name: .NCUserThreadsUpdated, object: self, userInfo: userInfo)

                completionBlock(threads, nil)
            } else {
                completionBlock(nil, NSError(domain: "", code: 0, userInfo: nil))
            }
        }
    }

    @nonobjc
    public func getThread(for accountId: String, in roomToken: String, threadId: Int, completionBlock: @escaping (_ thread: NCThread?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = roomToken.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else {
            completionBlock(nil)
            return
        }

        let apiVersion = self.chatAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/threads/\(threadId)", withAPIVersion: apiVersion, for: account)

        apiSessionManager.getOcs(urlString, account: account, parameters: nil) { ocs, _ in
            guard let threadDict = ocs?.dataDict as? [String: Any] else {
                completionBlock(nil)
                return
            }

            let thread = NCThread(dictionary: threadDict, andAccountId: accountId)
            NCThread.storeOrUpdateThreads([thread])
            completionBlock(thread)
        }
    }

    @nonobjc
    public func setNotificationLevelForThread(for accountId: String, in roomToken: String, threadId: Int, level: Int, completionBlock: @escaping (_ thread: NCThread?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = roomToken.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else {
            completionBlock(nil)
            return
        }

        let apiVersion = self.chatAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/threads/\(threadId)/notify", withAPIVersion: apiVersion, for: account)

        let parameters: [String: Int] = [
            "level": level
        ]

        apiSessionManager.postOcs(urlString, account: account, parameters: parameters) { ocs, _ in
            guard let threadDict = ocs?.dataDict as? [String: Any] else {
                completionBlock(nil)
                return
            }

            let thread = NCThread(dictionary: threadDict, andAccountId: accountId)
            NCThread.storeOrUpdateThreads([thread])
            completionBlock(thread)
        }
    }
}
