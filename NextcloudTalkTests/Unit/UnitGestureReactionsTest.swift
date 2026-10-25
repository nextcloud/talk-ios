//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation
import XCTest
@testable import NextcloudTalk

final class UnitGestureReactionsTest: XCTestCase {

    func testGestureReactionMapping() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("Gesture reactions need iOS 17") }

        XCTAssertEqual(CameraEffects.callReaction(for: .thumbsUp), "👍")
        XCTAssertEqual(CameraEffects.callReaction(for: .thumbsDown), "👎")
        XCTAssertEqual(CameraEffects.callReaction(for: .heart), "❤️")
        XCTAssertEqual(CameraEffects.callReaction(for: .balloons), "🎉")
        XCTAssertEqual(CameraEffects.callReaction(for: .confetti), "🎉")
        XCTAssertEqual(CameraEffects.callReaction(for: .fireworks), "🎉")
        XCTAssertEqual(CameraEffects.callReaction(for: .lasers), "🤩")
        XCTAssertEqual(CameraEffects.callReaction(for: .rain), "😥")
    }
}
