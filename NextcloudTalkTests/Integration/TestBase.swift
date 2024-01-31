//
// Copyright (c) 2023 Marcel Müller <marcel-mueller@gmx.de>
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

import XCTest
import Foundation
@testable import NextcloudTalk

class TestBase: XCTestCase {

    var appToken = ""
    var apiSessionManager: NCAPISessionManager?

    func setupAppToken() {
        let appPasswordRoute = "\(TestConstants.server)/ocs/v2.php/core/getapppassword"

        let credentialsString = "\(TestConstants.username):\(TestConstants.password)"
        let authHeader = "Basic \(credentialsString.data(using: .utf8)!.base64EncodedString())"

        let configuration = URLSessionConfiguration.default
        let apiSessionManager = NCAPISessionManager(sessionConfiguration: configuration)
        apiSessionManager.requestSerializer.setValue(authHeader, forHTTPHeaderField: "Authorization")

        let exp = expectation(description: "\(#function)\(#line)")

        _ = apiSessionManager.get(appPasswordRoute, parameters: nil, progress: nil) { _, result in
            if let resultDict = result as? [String: AnyObject],
               let ocs = resultDict["ocs"] as? [String: AnyObject],
               let data = ocs["data"] as? [String: AnyObject],
               let apppassword = data["apppassword"] as? String {

                self.appToken = apppassword
                exp.fulfill()
            }
        } failure: { _, error in
            print(error)
            exp.fulfill()
        }

        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)
    }

    func setupApiSessionManager() {
        let authHeader = "Basic \(self.appToken.data(using: .utf8)!.base64EncodedString())"

        let configuration = URLSessionConfiguration.default
        let apiSessionManager = NCAPISessionManager(sessionConfiguration: configuration)
        apiSessionManager.requestSerializer.setValue(authHeader, forHTTPHeaderField: "Authorization")

        self.apiSessionManager = apiSessionManager
    }

    override func setUpWithError() throws {
        if appToken.isEmpty {
            let accountId = NCDatabaseManager.sharedInstance().accountId(forUser: TestConstants.username, inServer: TestConstants.server)
            let talkAccount = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId)

            // Remove the account in case it already exists
            if talkAccount != nil {
                NCSettingsController.sharedInstance().logoutAccount(withAccountId: accountId, withCompletionBlock: nil)
            }

            self.setupAppToken()
            self.setupApiSessionManager()

            NCSettingsController.sharedInstance().addNewAccount(forUser: TestConstants.username, withToken: appToken, inServer: TestConstants.server)
            let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
            let exp = expectation(description: "\(#function)\(#line)")

            // Make sure the capabilities are up to date
            NCSettingsController.sharedInstance().getCapabilitiesForAccountId(activeAccount.accountId) { _ in
                exp.fulfill()
            }

            waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)
        }

        XCTAssertFalse(appToken.isEmpty)
        XCTAssertNotNil(apiSessionManager)
    }

}
