//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Testing
@testable import NextcloudTalk

@Suite(.serialized)
final class IntegrationCapabilities: TestBase {

    @Test func `capabilities server URL`() async {
        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().getServerCapabilities(forServer: TestConstants.server) { serverCapabilities, error in
                #expect(error == nil)

                let capabilities = serverCapabilities!["capabilities"] as! [AnyHashable: Any]

                // No core for guests
                // #expect(capabilities["core"] != nil)
                #expect(capabilities["spreed"] != nil)

                continuation.resume()
            }
        }
    }

    @Test func `capabilities account`() async {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().getServerCapabilities(forAccount: activeAccount) { serverCapabilities, error in
                #expect(error == nil)

                let capabilities = serverCapabilities!["capabilities"] as! [AnyHashable: Any]

                #expect(capabilities["core"] != nil)
                #expect(capabilities["spreed"] != nil)

                continuation.resume()
            }
        }
    }

}
