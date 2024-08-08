//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitNCDatabaseManager: TestBaseRealm {

    func testSavingExternalSignalingVersion() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let testVersion = "Test version"
        let testVersionUpdated = "Test version updated"

        updateCapabilities { cap in
            cap.externalSignalingServerVersion = testVersion
        }

        var capabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId)
        XCTAssertEqual(capabilities?.externalSignalingServerVersion, testVersion)

        NCDatabaseManager.sharedInstance().setExternalSignalingServerVersion(testVersionUpdated, forAccountId: activeAccount.accountId)

        capabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId)
        XCTAssertEqual(capabilities?.externalSignalingServerVersion, testVersionUpdated)
    }
}
