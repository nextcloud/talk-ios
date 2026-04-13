//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
import Foundation
@testable import NextcloudTalk

final class IntegrationSettingsTest: TestBase {

    func testReadPrivacy() async throws {
        try skipWithoutCapability(capability: kCapabilityChatReadStatus)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let accountId = activeAccount.accountId

        // Don't check initial state here, as otherwise the tests are not repeatable
        // XCTAssertFalse(NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: accountId)!.readStatusPrivacy)

        let exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().setReadStatusPrivacySettingEnabled(true, forAccount: activeAccount) { error in
            XCTAssertNil(error)

            NCSettingsController.sharedInstance().getCapabilitiesForAccountId(accountId) { error in
                XCTAssertNil(error)

                XCTAssertTrue(NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: accountId)!.readStatusPrivacy)
                exp.fulfill()
            }
        }

        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)
    }

    func testTypingPrivacy() async throws {
        try skipWithoutCapability(capability: kCapabilityTypingIndicators)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let accountId = activeAccount.accountId

        // Don't check initial state here, as otherwise the tests are not repeatable
        // XCTAssertFalse(NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: accountId)!.typingPrivacy)

        let exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().setTypingPrivacySettingEnabled(true, forAccount: activeAccount) { error in
            XCTAssertNil(error)

            NCSettingsController.sharedInstance().getCapabilitiesForAccountId(accountId) { error in
                XCTAssertNil(error)

                XCTAssertTrue(NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: accountId)!.typingPrivacy)
                exp.fulfill()
            }
        }

        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)
    }

}
