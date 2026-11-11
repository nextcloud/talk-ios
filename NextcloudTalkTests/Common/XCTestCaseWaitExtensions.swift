//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
import Foundation

extension XCTestCase {

    // For state that settles asynchronously, e.g. delivered notifications
    func waitUntil(timeout: Double = TestConstants.timeoutShort, _ condition: () async throws -> Bool) async rethrows -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            if try await condition() {
                return true
            }

            try? await Task.sleep(for: .milliseconds(100))
        } while Date() < deadline

        return false
    }
}
