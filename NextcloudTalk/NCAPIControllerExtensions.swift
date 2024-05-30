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

    func getOcsResponse(data: Any?) -> [String: AnyObject]? {
        guard let resultDict = data as? [String: AnyObject],
              let ocs = resultDict["ocs"] as? [String: AnyObject]
        else { return nil }

        return ocs
    }

    func getOcsDictResponse(data: Any?) -> [String: AnyObject]? {
        guard let ocs = self.getOcsResponse(data: data),
              let ocsData = ocs["data"] as? [String: AnyObject]
        else { return nil }

        return ocsData
    }

    func getOcsArrayDictResponse(data: Any?) -> [[String: AnyObject]]? {
        guard let ocs = self.getOcsResponse(data: data),
              let ocsData = ocs["data"] as? [[String: AnyObject]]
        else { return nil }

        return ocsData
    }

    func checkResponseHeaders(withDataTask task: URLSessionTask?, forAccount account: TalkAccount) {
        guard let task,
              let response = task.response,
              let headers = self.getResponseHeaders(response)
        else { return }

        self.checkResponseHeaders(headers, for: account)
    }

    // MARK: - Rooms Controller

    public func getRooms(forAccount account: TalkAccount, updateStatus: Bool, modifiedSince: Int, completionBlock: @escaping (_ rooms: [[String: AnyObject]]?, _ error: Error?, _ statusCode: Int) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId)
        else {
            completionBlock(nil, NSError(domain: "", code: 0), 0)
            return
        }

        let apiVersion = self.conversationAPIVersion(for: account)
        var urlString = self.getRequestURL(forEndpoint: "room", withAPIVersion: apiVersion, for: account)

        let parameters: [String: Any] = [
            "noStatusUpdate": !updateStatus,
            "modifiedSince": modifiedSince
        ]

        // Since we are using "modifiedSince" only in background fetches
        // we will request including user status only when getting the complete room list
        if serverCapabilities.userStatus, modifiedSince == 0 {
            urlString = urlString.appending("?includeStatus=true")
        }

        apiSessionManager.get(urlString, parameters: parameters, progress: nil) { task, result in
            self.checkResponseHeaders(withDataTask: task, forAccount: account)

            // TODO: Move away from generic dictionary return type
            // let rooms = data.compactMap { NCRoom(dictionary: $0, andAccountId: account.accountId) }
            completionBlock(self.getOcsArrayDictResponse(data: result), nil, 0)
        } failure: { task, error in
            let statusCode = self.getResponseStatusCode(task?.response)
            self.checkResponseStatusCode(statusCode, for: account)

            completionBlock(nil, error, statusCode)
        }
    }

    public func getRoom(forAccount account: TalkAccount, withToken token: String, completionBlock: @escaping (_ room: [String: AnyObject]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else {
            completionBlock(nil, NSError(domain: "", code: 0))
            return
        }

        let apiVersion = self.conversationAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "room/\(encodedToken)", withAPIVersion: apiVersion, for: account)

        apiSessionManager.get(urlString, parameters: nil, progress: nil) { task, result in
            self.checkResponseHeaders(withDataTask: task, forAccount: account)

            completionBlock(self.getOcsDictResponse(data: result), nil)
        } failure: { task, error in
            let statusCode = self.getResponseStatusCode(task?.response)
            self.checkResponseStatusCode(statusCode, for: account)

            completionBlock(nil, error)
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

        apiSessionManager.post(urlString, parameters: nil, progress: nil) { _, _ in
            completionBlock(true)
        } failure: { _, _ in
            completionBlock(false)
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

        apiSessionManager.delete(urlString, parameters: nil) { _, _ in
            completionBlock(true)
        } failure: { _, _ in
            completionBlock(false)
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

        apiSessionManager.get(urlString, parameters: nil, progress: nil) { _, result in
            if let ocs = self.getOcsResponse(data: result),
               let data = ocs["data"] as? [[String: AnyObject]] {

                let invitations = data.map { FederationInvitation(dictionary: $0, for: accountId)}
                completionBlock(invitations)
            } else {
                completionBlock(nil)
            }

            NCDatabaseManager.sharedInstance().updateLastFederationInvitationUpdate(forAccountId: accountId, withTimestamp: Int(Date().timeIntervalSince1970))
        } failure: { _, _ in
            completionBlock(nil)
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

        apiSessionManager.get(urlString, parameters: nil, progress: nil) { task, result in
            if let ocs = self.getOcsResponse(data: result),
               let data = ocs["data"] as? [String: AnyObject],
               let response = task.response,
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
        } failure: { _, _ in
            completionBlock(nil, nil)
        }
    }

    // MARK: - Mentions

    public func getMentionSuggestions(for accountId: String, in roomToken: String, with searchString: String, completionBlock: @escaping (_ invitations: [MentionSuggestion]?) -> Void) {
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

        apiSessionManager.get(urlString, parameters: parameters, progress: nil) { _, result in
            if let ocs = self.getOcsResponse(data: result),
               let data = ocs["data"] as? [[String: AnyObject]] {

                let mentions = data.map { MentionSuggestion(dictionary: $0)}
                completionBlock(mentions)
            } else {
                completionBlock(nil)
            }

            NCDatabaseManager.sharedInstance().updateLastFederationInvitationUpdate(forAccountId: accountId, withTimestamp: Int(Date().timeIntervalSince1970))
        } failure: { _, _ in
            completionBlock(nil)
        }
    }
}
