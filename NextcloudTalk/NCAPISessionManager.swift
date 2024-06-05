//
// Copyright (c) 2024 Marcel Müller <marcel-mueller@gmx.de>
//
// Author Ivan Sein <ivan@nextcloud.com>
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

@objcMembers public class NCAPISessionManager: NCBaseSessionManager {

    init(configuration: URLSessionConfiguration) {
        super.init(configuration: configuration, responseSerializer: AFJSONResponseSerializer(), requestSerializer: AFHTTPRequestSerializer())

        self.requestSerializer.setValue("application/json", forHTTPHeaderField: "Accept")
        self.requestSerializer.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
    }

    private func checkHeaders(for task: URLSessionDataTask, for account: TalkAccount) {
        guard let response = task.response as? HTTPURLResponse else { return }

        if let modifiedSince = response.allHeaderFields["x-nextcloud-talk-modified-before"] as? String, !modifiedSince.isEmpty {
            NCDatabaseManager.sharedInstance().updateLastModifiedSince(forAccountId: account.accountId, with: modifiedSince)
        }

        if let configurationHash = response.allHeaderFields["x-nextcloud-talk-hash"] as? String, configurationHash != account.lastReceivedConfigurationHash {
            if account.lastReceivedConfigurationHash != nil {
                // We previously stored a configuration hash which now changed -> Update settings and capabilities
                let userInfo: [AnyHashable: Any] = [
                    "accountId": account.accountId,
                    "configurationHash": configurationHash
                ]

                NotificationCenter.default.post(name: .NCTalkConfigurationHashChanged, object: self, userInfo: userInfo)
            } else {
                NCDatabaseManager.sharedInstance().updateTalkConfigurationHash(forAccountId: account.accountId, withHash: configurationHash)
            }
        }
    }

    private func checkStatusCode(for task: URLSessionDataTask, for account: TalkAccount) {
        guard let response = task.response as? HTTPURLResponse else { return }
        let statusCode = response.statusCode

        let userInfo: [AnyHashable: Any] = ["accountId": account.accountId]

        switch statusCode {
        case 401:
            NotificationCenter.default.post(name: .NCTokenRevokedResponseReceived, object: self, userInfo: userInfo)
        case 426:
            NotificationCenter.default.post(name: .NCUpgradeRequiredResponseReceived, object: self, userInfo: userInfo)
        case 503:
            NotificationCenter.default.post(name: .NCServerMaintenanceMode, object: self, userInfo: userInfo)
        default:
            break
        }
    }

    @discardableResult
    public func getOcs(_ URLString: String, account: TalkAccount, parameters: Any? = nil, progress downloadProgress: ((Progress) -> Void)? = nil, checkResponseHeaders: Bool = true, checkResponseStatusCode: Bool = true, completion: ((OcsResponse?, (any Error)?) -> Void)?) -> URLSessionDataTask? {
        return self.get(URLString, parameters: parameters, progress: downloadProgress) { task, data in
            if checkResponseHeaders {
                self.checkHeaders(for: task, for: account)
            }

            completion?(OcsResponse(withData: data, withTask: task), nil)
        } failure: { task, error in
            if checkResponseStatusCode, let task {
                self.checkStatusCode(for: task, for: account)
            }

            completion?(nil, error)
        }
    }

    @discardableResult
    public func postOcs(_ URLString: String, account: TalkAccount, parameters: Any? = nil, progress downloadProgress: ((Progress) -> Void)? = nil, checkResponseStatusCode: Bool = true, completion: ((OcsResponse?, (any Error)?) -> Void)?) -> URLSessionDataTask? {
        return self.post(URLString, parameters: parameters, progress: downloadProgress) { task, data in
            completion?(OcsResponse(withData: data, withTask: task), nil)
        } failure: { task, error in
            if checkResponseStatusCode, let task {
                self.checkStatusCode(for: task, for: account)
            }

            completion?(nil, error)
        }
    }

    @discardableResult
    public func putOcs(_ URLString: String, account: TalkAccount, parameters: Any? = nil, checkResponseStatusCode: Bool = true, completion: ((OcsResponse?, (any Error)?) -> Void)?) -> URLSessionDataTask? {
        return self.put(URLString, parameters: parameters) { task, data in
            completion?(OcsResponse(withData: data, withTask: task), nil)
        } failure: { task, error in
            if checkResponseStatusCode, let task {
                self.checkStatusCode(for: task, for: account)
            }

            completion?(nil, error)
        }
    }

    @discardableResult
    public func deleteOcs(_ URLString: String, account: TalkAccount, parameters: Any? = nil, checkResponseStatusCode: Bool = true, completion: ((OcsResponse?, (any Error)?) -> Void)?) -> URLSessionDataTask? {
        return self.delete(URLString, parameters: parameters) { task, data in
            completion?(OcsResponse(withData: data, withTask: task), nil)
        } failure: { task, error in
            if checkResponseStatusCode, let task {
                self.checkStatusCode(for: task, for: account)
            }

            completion?(nil, error)
        }
    }
}
