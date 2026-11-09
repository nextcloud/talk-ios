//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

// Launch arguments used by the UI tests, all others only apply together with -TestEnvironment:
//   -TestEnvironment                   debug allocation label and test only UI
//   -TestResetAccounts                remove all accounts, the app starts at the login screen
//   -TestAccountServer <url>
//   -TestAccountUser <user>
//   -TestAccountPassword <password>    remove all accounts and log in with this one
class TestEnvironment {

    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-TestEnvironment")

    static let shared = TestEnvironment()

    // While set, NCConnectionController must not evaluate the app state, it would present the login screen
    private(set) var isSettingUpAccounts = false

    private var didSetUp = false

    func setUpIfNeeded() {
        // Launch arguments apply once per process, not again for every scene that connects
        guard TestEnvironment.isEnabled, !didSetUp else { return }
        didSetUp = true

        let defaults = UserDefaults.standard
        let server = defaults.string(forKey: "TestAccountServer")
        let user = defaults.string(forKey: "TestAccountUser")
        let password = defaults.string(forKey: "TestAccountPassword")
        let resetAccounts = ProcessInfo.processInfo.arguments.contains("-TestResetAccounts")

        let addAccount = server != nil || user != nil || password != nil

        guard resetAccounts || addAccount else { return }

        isSettingUpAccounts = true
        removeAllAccounts()

        guard let server, let user, let password else {
            if addAccount {
                NCLog.log("TestEnvironment: -TestAccountServer, -TestAccountUser and -TestAccountPassword are all required")
            }

            finishSetup()
            return
        }

        NCAPIController.sharedInstance().getAppPassword(forServer: server, withUsername: user, andPassword: password) { appToken in
            DispatchQueue.main.async {
                if let appToken {
                    NCSettingsController.sharedInstance().addNewAccount(forUser: user, withToken: appToken, inServer: server)
                } else {
                    NCLog.log("TestEnvironment: Failed to get an app password for \(user) on \(server)")
                }

                self.finishSetup()
            }
        }
    }

    private func removeAllAccounts() {
        // Collect the ids first, the account objects are invalidated once removed from the database
        let accountIds = NCDatabaseManager.sharedInstance().allAccounts().map(\.accountId)

        for accountId in accountIds {
            NCSettingsController.sharedInstance().logoutAccount(withAccountId: accountId, withCompletionBlock: nil)
        }
    }

    private func finishSetup() {
        isSettingUpAccounts = false
        NCConnectionController.shared.checkAppState()
    }
}
