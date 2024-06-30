//
// Copyright (c) 2024 Marcel Müller <marcel-mueller@gmx.de>
//
// Author Marcel Müller <marcel-mueller@gmx.de>
//
// GNU GPL version 3 or any later version
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation

@objc extension NCAPIController {

    // MARK: - Rooms Controller

    public func getRooms(forAccount account: TalkAccount, updateStatus: Bool, modifiedSince: Int, completionBlock: @escaping (_ rooms: [[String: AnyObject]]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else { return }

        let apiVersion = self.conversationAPIVersion(for: account)
        var urlString = self.getRequestURL(forEndpoint: "room", withAPIVersion: apiVersion, for: account)
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

        apiSessionManager.getOcs(urlString, account: account, parameters: parameters) { ocs, error in
            // TODO: Move away from generic dictionary return type
            // let rooms = ocs?.dataArrayDict.compactMap { NCRoom(dictionary: $0, andAccountId: account.accountId) }
            completionBlock(ocs?.dataArrayDict, error)
        }
    }

    public func getRoom(forAccount account: TalkAccount, withToken token: String, completionBlock: @escaping (_ room: [String: AnyObject]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let apiVersion = self.conversationAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "room/\(encodedToken)", withAPIVersion: apiVersion, for: account)

        apiSessionManager.getOcs(urlString, account: account) { ocs, error in
            completionBlock(ocs?.dataDict, error)
        }
    }

    public func getNoteToSelfRoom(forAccount account: TalkAccount, completionBlock: @escaping (_ room: [String: AnyObject]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else { return }

        let apiVersion = self.conversationAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "room/note-to-self", withAPIVersion: apiVersion, for: account)

        apiSessionManager.getOcs(urlString, account: account) { ocs, error in
            completionBlock(ocs?.dataDict, error)
        }
    }

    public func getListableRooms(forAccount account: TalkAccount, withSerachTerm searchTerm: String?, completionBlock: @escaping (_ rooms: [NCRoom]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else { return }

        let apiVersion = self.conversationAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "listed-room", withAPIVersion: apiVersion, for: account)
        var parameters: [String: Any] = [:]

        if let searchTerm, !searchTerm.isEmpty {
            parameters["searchTerm"] = searchTerm
        }

        apiSessionManager.getOcs(urlString, account: account, parameters: parameters) { ocs, error in
            let rooms = ocs?.dataArrayDict?.compactMap { NCRoom(dictionary: $0, andAccountId: account.accountId) }
            completionBlock(rooms, error)
        }
    }

    public func createRoom(forAccount account: TalkAccount, withInvite invite: String?, ofType roomType: NCRoomType, andName roomName: String?, completionBlock: @escaping (_ room: NCRoom?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else { return }

        let apiVersion = self.conversationAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "room", withAPIVersion: apiVersion, for: account)
        var parameters: [String: Any] = ["roomType": roomType.rawValue]

        if let invite, !invite.isEmpty {
            parameters["invite"] = invite
        }

        if let roomName, !roomName.isEmpty {
            parameters["roomName"] = roomName
        }

        apiSessionManager.postOcs(urlString, account: account, parameters: parameters) { ocs, error in
            let room = NCRoom(dictionary: ocs?.dataDict, andAccountId: account.accountId)
            completionBlock(room, error)
        }
    }

    public func renameRoom(_ token: String, forAccount account: TalkAccount, withName roomName: String, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let apiVersion = self.conversationAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "room/\(encodedToken)", withAPIVersion: apiVersion, for: account)
        let parameters: [String: String] = ["roomName": roomName]

        apiSessionManager.putOcs(urlString, account: account, parameters: parameters) { _, error in
            completionBlock(error)
        }
    }

    public func setRoomDescription(_ description: String?, forRoom token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let apiVersion = self.conversationAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "room/\(encodedToken)/description", withAPIVersion: apiVersion, for: account)
        let parameters: [String: String] = ["description": description ?? ""]

        apiSessionManager.putOcs(urlString, account: account, parameters: parameters) { _, error in
            completionBlock(error)
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

            NCDatabaseManager.sharedInstance().updateLastFederationInvitationUpdate(forAccountId: accountId, withTimestamp: Int(Date().timeIntervalSince1970))
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

        let apiVersion = self.conversationAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "room/\(encodedToken)/capabilities", withAPIVersion: apiVersion, for: account)

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

    // MARK: - Avatars

    public func getDateHash() -> String {
        // TODO: Mark private when swift migration is done
        let dateString = NCUtils.getDate(fromDate: Date())

        return String(NCUtils.sha1(fromString: dateString).prefix(16))
    }

    // MARK: - Ban

    public func banActor(for accountId: String, in roomToken: String, with actorType: String, with actorId: String, with internalNote: String?, completionBlock: @escaping (_ success: Bool) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else {
            completionBlock(false)
            return
        }

        let apiVersion = self.banAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "ban/\(roomToken)", withAPIVersion: apiVersion, for: account)

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
              let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else {
            completionBlock(nil)
            return
        }

        let apiVersion = self.banAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "ban/\(roomToken)", withAPIVersion: apiVersion, for: account)

        apiSessionManager.get(urlString, parameters: nil, progress: nil) { _, result in
            if let ocs = self.getOcsResponse(data: result),
               let data = ocs["data"] as? [[String: AnyObject]] {

                let actorBans = data.map { BannedActor(dictionary: $0)}
                completionBlock(actorBans)
            } else {
                completionBlock(nil)
            }
        } failure: { _, _ in
            completionBlock(nil)
        }
    }

    public func unbanActor(for accountId: String, in roomToken: String, with banId: Int, completionBlock: @escaping (_ success: Bool) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else {
            completionBlock(false)
            return
        }

        let apiVersion = self.banAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "ban/\(roomToken)", withAPIVersion: apiVersion, for: account)

        let parameters: [String: Any] = [
            "banId": banId
        ]

        apiSessionManager.delete(urlString, parameters: parameters) { _, _ in
            completionBlock(true)
        } failure: { _, _ in
            completionBlock(false)
        }
    }
}
