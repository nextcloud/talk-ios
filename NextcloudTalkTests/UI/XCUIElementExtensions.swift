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

    // A swipeDown is too short to trigger the refresh control when the search bar is revealed first
    func pullToRefresh() {
        let start = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let end = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        start.press(forDuration: 0.1, thenDragTo: end)
    }
}
