// From: https://gist.github.com/sceiler/3b0f87bb692e556916ba097c1db95295

// Apple's testing framework for UI tests is notoriously slow.
// It is not uncommon to wait a couple of hours for UI tests to finish
// and making them run as part of a CI build / nightly run it is still acceptable.
// Using other UI testing frameworks like KIF, Earl Grey (Google) or
// iOSSnapshotTestCase (formerly Facebook, now Uber) can only complement Apple's
// own framework as they achieve their faster speed using different testing approaches
// and/or "workarounds".
// The small extension I have developed dramatically increases the quantity of lookups
// for the existence of a XCUIElement.
// The impact is probably a higher usage of CPU/RAM but this should be negligible.

import Foundation
import XCTest

/// Increase amount of lookup for XCUIElement.waitForExistence() during
/// a timeframe.
/// - Parameter timeout: The maximum amount of seconds to wait for
/// - Returns: True if the element comes into existence during the specified timeout
extension XCUIElement {
    func waitForExist(timeout: TimeInterval) -> Bool {
        let maxTries = timeout * 10

        for i in 0..<Int(maxTries) {
            if waitForExistence(timeout: 0.1) {
                return true
            }

            if i == Int(maxTries) - 1 {
                return false
            }
        }
        return false
    }
}
