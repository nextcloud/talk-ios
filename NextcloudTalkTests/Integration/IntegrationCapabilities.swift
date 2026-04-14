//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
import Foundation
@testable import NextcloudTalk

final class IntegrationCapabilities: TestBase {

    func testCapabilitiesServerUrl() async throws {
        let exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().getServerCapabilities(forServer: TestConstants.server) { serverCapabilities, error in
            XCTAssertNil(error)

            let capabilities = serverCapabilities!["capabilities"] as! [AnyHashable: Any]

            // No core for guests
            // XCTAssertNotNil(capabilities["core"])
            XCTAssertNotNil(capabilities["spreed"])

            exp.fulfill()
        }

        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)
    }

    func testCapabilitiesAccount() async throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        let exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().getServerCapabilities(forAccount: activeAccount) { serverCapabilities, error in
            XCTAssertNil(error)

            let capabilities = serverCapabilities!["capabilities"] as! [AnyHashable: Any]

            XCTAssertNotNil(capabilities["core"])
            XCTAssertNotNil(capabilities["spreed"])
            exp.fulfill()
        }

        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)
    }

}
