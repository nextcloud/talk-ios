//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
import Foundation
@testable import NextcloudTalk

final class IntegrationContactsTest: TestBase {

    func testGetContacts() async throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        let exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().getContacts(forAccount: activeAccount, forRoom: nil, forGroupRoom: false, withSearchParam: nil) { contacts, error in
            XCTAssertNotNil(contacts)
            XCTAssertNil(error)

            XCTAssertTrue(contacts!.contains(where: { $0.userId == "alice" }))

            exp.fulfill()
        }

        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)
    }

    func testSearchUsers() async throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        if !NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId)!.absenceSupported {
            // When testing against Nextcloud 23, an internal server error is thrown, as we do not provide the 'itemType' parameter
            throw XCTSkip("Only test when absence (OOO) is supported server-side")
        }

        let exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().searchUsers(forAccount: activeAccount, withSearchParam: nil) { contacts, error in
            XCTAssertNotNil(contacts)
            XCTAssertNil(error)

            XCTAssertTrue(contacts!.contains(where: { $0.userId == "alice" }))

            exp.fulfill()
        }

        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)
    }

}
