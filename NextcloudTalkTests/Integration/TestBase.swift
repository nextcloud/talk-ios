//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
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
        let apiSessionManager = NCAPISessionManager(configuration: configuration)
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
        let apiSessionManager = NCAPISessionManager(configuration: configuration)
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
            exp.expectedFulfillmentCount = 2

            // Make sure the capabilities are up to date
            NCSettingsController.sharedInstance().getCapabilitiesForAccountId(activeAccount.accountId) { _ in
                exp.fulfill()
            }

            // Fetch to user profile to have a complete account object
            NCSettingsController.sharedInstance().getUserProfile(forAccountId: activeAccount.accountId) { _ in
                exp.fulfill()
            }

            waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)
        }

        XCTAssertFalse(appToken.isEmpty)
        XCTAssertNotNil(apiSessionManager)
    }

}
