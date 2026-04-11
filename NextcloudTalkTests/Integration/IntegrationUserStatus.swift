//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
import Foundation
@testable import NextcloudTalk

final class IntegrationUserStatus: TestBase {

    func testUserStatus() async throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        if !NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId)!.userStatus {
            throw XCTSkip("Only test when user-status is supported server-side")
        }

        let exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().setUserStatus(kUserStatusOnline, forAccount: activeAccount) { error in
            XCTAssertNil(error)

            NCAPIController.sharedInstance().getUserStatus(forAccount: activeAccount) { userStatus in
                XCTAssertEqual(userStatus?.status, kUserStatusOnline)

                NCAPIController.sharedInstance().setUserStatus(kUserStatusInvisible, forAccount: activeAccount) { error in
                    XCTAssertNil(error)

                    NCAPIController.sharedInstance().getUserStatus(forAccount: activeAccount) { userStatus in
                        XCTAssertEqual(userStatus?.status, kUserStatusInvisible)

                        exp.fulfill()
                    }
                }
            }
        }

        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)
    }

}
