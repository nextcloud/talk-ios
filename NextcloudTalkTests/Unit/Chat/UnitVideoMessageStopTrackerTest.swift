//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitVideoMessageStopTrackerTest: XCTestCase {

    func testIsNotStoppingInitially() {
        XCTAssertFalse(VideoMessageStopTracker().isStopping)
    }

    func testIsStoppingUntilTheStopEnded() {
        var tracker = VideoMessageStopTracker()

        tracker.stopBegan()
        XCTAssertTrue(tracker.isStopping)

        tracker.stopEnded()
        XCTAssertFalse(tracker.isStopping)
    }

    func testStaysStoppingWhileAnyStopIsPending() {
        var tracker = VideoMessageStopTracker()

        tracker.stopBegan()
        tracker.stopBegan()
        tracker.stopEnded()
        XCTAssertTrue(tracker.isStopping)

        tracker.stopEnded()
        XCTAssertFalse(tracker.isStopping)
    }

    func testUnbalancedEndDoesNotBlockTheNextStop() {
        var tracker = VideoMessageStopTracker()

        tracker.stopEnded()
        XCTAssertFalse(tracker.isStopping)

        tracker.stopBegan()
        XCTAssertTrue(tracker.isStopping)
    }
}
