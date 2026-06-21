//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Testing
@testable import NextcloudTalk

@Suite(.serialized)
final class IntegrationSettingsTest: TestBase {

    @Test func `read privacy`() async throws {
        try skipWithoutCapability(capability: kCapabilityChatReadStatus)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let accountId = activeAccount.accountId

        // Don't check initial state here, as otherwise the tests are not repeatable
        // #expect(!NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: accountId)!.readStatusPrivacy)

        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().setReadStatusPrivacySettingEnabled(true, forAccount: activeAccount) { error in
                #expect(error == nil)

                NCSettingsController.sharedInstance().getCapabilitiesForAccountId(accountId) { error in
                    #expect(error == nil)

                    #expect(NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: accountId)!.readStatusPrivacy)
                    continuation.resume()
                }
            }
        }
    }

    @Test func `typing privacy`() async throws {
        try skipWithoutCapability(capability: kCapabilityTypingIndicators)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let accountId = activeAccount.accountId

        // Don't check initial state here, as otherwise the tests are not repeatable
        // #expect(!NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: accountId)!.typingPrivacy)

        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().setTypingPrivacySettingEnabled(true, forAccount: activeAccount) { error in
                #expect(error == nil)

                NCSettingsController.sharedInstance().getCapabilitiesForAccountId(accountId) { error in
                    #expect(error == nil)

                    #expect(NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: accountId)!.typingPrivacy)
                    continuation.resume()
                }
            }
        }
    }

}
