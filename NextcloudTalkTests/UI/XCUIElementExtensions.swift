//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import XCTest

extension XCUIElement {

    func scrollTo(_ element: XCUIElement, maxScrolls: Int = 10) {
        var attempts = 0

        while !element.isHittable && attempts < maxScrolls {
            swipeUp()
            attempts += 1
        }

        XCTAssertTrue(element.isHittable, "Element not found after scrolling.")
    }
}
