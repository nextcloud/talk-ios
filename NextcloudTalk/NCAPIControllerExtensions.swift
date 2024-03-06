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
        let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId)!
        let apiVersion = self.federationAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "federation/invitation", withAPIVersion: apiVersion, for: account)

        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else {
            completionBlock(nil)
            return
        }

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

    public func getRoomCapabilities(for accountId: String, token: String, completionBlock: @escaping (_ roomCapabilities: [String: AnyObject]?, _ proxyHash: String?) -> Void) {
        guard let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else { return }
        let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId)!
        let apiVersion = self.conversationAPIVersion(for: account)
        let urlString = self.getRequestURL(forEndpoint: "room/\(encodedToken)/capabilities", withAPIVersion: apiVersion, for: account)

        guard let apiSessionManager = self.apiSessionManagers.object(forKey: account.accountId) as? NCAPISessionManager
        else {
            completionBlock(nil, nil)
            return
        }

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
}
