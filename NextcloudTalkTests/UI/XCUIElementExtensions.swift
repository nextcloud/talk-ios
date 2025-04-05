//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import XCTest

extension XCUIElement {

    // See: https://stackoverflow.com/a/63089781
    /**
     * Waits the specified amount of time for the element’s `exists` property to become `false`.
     *
     * - Parameter timeout: The amount of time to wait.
     * - Returns: `false` if the timeout expires without the element coming out of existence.
     */
    func waitForNonExistence(timeout: TimeInterval) -> Bool {

        let timeStart = Date().timeIntervalSince1970

        while Date().timeIntervalSince1970 <= (timeStart + timeout) {
            if !exists { return true }

            usleep(500)
        }

        return false
    }
}
