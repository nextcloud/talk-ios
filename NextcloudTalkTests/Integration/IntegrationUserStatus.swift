//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Testing
@testable import NextcloudTalk

@Suite(.serialized)
final class IntegrationUserStatus: TestBase {

    @Test func `user status`() async throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        if !NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId)!.userStatus {
            try Test.cancel("Only test when user-status is supported server-side")
        }

        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().setUserStatus(kUserStatusOnline, forAccount: activeAccount) { error in
                #expect(error == nil)

                NCAPIController.sharedInstance().getUserStatus(forAccount: activeAccount) { userStatus in
                    #expect(userStatus?.status == kUserStatusOnline)

                    NCAPIController.sharedInstance().setUserStatus(kUserStatusInvisible, forAccount: activeAccount) { error in
                        #expect(error == nil)

                        NCAPIController.sharedInstance().getUserStatus(forAccount: activeAccount) { userStatus in
                            #expect(userStatus?.status == kUserStatusInvisible)

                            continuation.resume()
                        }
                    }
                }
            }
        }
    }

}
