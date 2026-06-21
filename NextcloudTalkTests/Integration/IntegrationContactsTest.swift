//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Testing
@testable import NextcloudTalk

@Suite(.serialized)
final class IntegrationContactsTest: TestBase {

    @Test func `get contacts`() async {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().getContacts(forAccount: activeAccount, forRoom: nil, forGroupRoom: false, withSearchParam: nil) { contacts, error in
                #expect(contacts != nil)
                #expect(error == nil)

                #expect(contacts!.contains(where: { $0.userId == "alice" }))

                continuation.resume()
            }
        }
    }

    @Test func `search users`() async throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        if !NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId)!.absenceSupported {
            // When testing against Nextcloud 23, an internal server error is thrown, as we do not provide the 'itemType' parameter
            try Test.cancel("Only test when absence (OOO) is supported server-side")
        }

        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().searchUsers(forAccount: activeAccount, withSearchParam: nil) { contacts, error in
                #expect(contacts != nil)
                #expect(error == nil)

                #expect(contacts!.contains(where: { $0.userId == "alice" }))

                continuation.resume()
            }
        }
    }

}
