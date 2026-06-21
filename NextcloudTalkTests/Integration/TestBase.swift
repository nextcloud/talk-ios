//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Testing
@testable import NextcloudTalk

@MainActor
class TestBase {

    var appToken = ""
    var apiSessionManager: NCAPISessionManager?

    init() async throws {
        let accountId = NCDatabaseManager.sharedInstance().accountId(forUser: TestConstants.username, inServer: TestConstants.server)
        let talkAccount = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId)

        // Remove the account in case it already exists
        if talkAccount != nil {
            NCSettingsController.sharedInstance().logoutAccount(withAccountId: accountId, withCompletionBlock: nil)
        }

        await setupAppToken()
        setupApiSessionManager()

        NCSettingsController.sharedInstance().addNewAccount(forUser: TestConstants.username, withToken: appToken, inServer: TestConstants.server)
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        // Make sure the capabilities are up to date
        await withCheckedContinuation { continuation in
            NCSettingsController.sharedInstance().getCapabilitiesForAccountId(activeAccount.accountId) { _ in
                continuation.resume()
            }
        }

        // Fetch the user profile to have a complete account object
        await withCheckedContinuation { continuation in
            NCSettingsController.sharedInstance().getUserProfile(forAccountId: activeAccount.accountId) { _ in
                continuation.resume()
            }
        }

        #expect(!appToken.isEmpty)
        #expect(apiSessionManager != nil)
    }

    private func setupAppToken() async {
        let appPasswordRoute = "\(TestConstants.server)/ocs/v2.php/core/getapppassword"

        let credentialsString = "\(TestConstants.username):\(TestConstants.password)"
        let authHeader = "Basic \(credentialsString.data(using: .utf8)!.base64EncodedString())"

        let configuration = URLSessionConfiguration.default
        let apiSessionManager = NCAPISessionManager(configuration: configuration)
        apiSessionManager.requestSerializer.setValue(authHeader, forHTTPHeaderField: "Authorization")

        await withCheckedContinuation { continuation in
            _ = apiSessionManager.get(appPasswordRoute, parameters: nil, progress: nil) { _, result in
                if let resultDict = result as? [String: AnyObject],
                   let ocs = resultDict["ocs"] as? [String: AnyObject],
                   let data = ocs["data"] as? [String: AnyObject],
                   let apppassword = data["apppassword"] as? String {

                    self.appToken = apppassword
                }

                continuation.resume()
            } failure: { _, error in
                print(error)
                continuation.resume()
            }
        }
    }

    private func setupApiSessionManager() {
        let authHeader = "Basic \(self.appToken.data(using: .utf8)!.base64EncodedString())"

        let configuration = URLSessionConfiguration.default
        let apiSessionManager = NCAPISessionManager(configuration: configuration)
        apiSessionManager.requestSerializer.setValue(authHeader, forHTTPHeaderField: "Authorization")

        self.apiSessionManager = apiSessionManager
    }

    /// A small reference-type helper to observe events fired from escaping notification or completion handlers.
    final class EventTracker {
        private(set) var signalCount = 0
        var fired: Bool { signalCount > 0 }
        func signal() { signalCount += 1 }
    }

    /// Pumps the run loop until `condition` is satisfied or the timeout elapses.
    /// Useful for events delivered asynchronously via the run loop (NSNotification) or completion handlers.
    /// Returns `true` if the condition was satisfied before the timeout.
    @discardableResult
    func wait(timeout: TimeInterval = TestConstants.timeoutLong, until condition: () -> Bool) async -> Bool {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) >= timeout {
                return false
            }
            try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
        }
        return true
    }
}
