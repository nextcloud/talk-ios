//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitChatEffectsTest: XCTestCase {

    @MainActor
    func testCelebrationDetection() {
        XCTAssertTrue(ChatEffects.isCelebration("Happy birthday 🎂"))
        XCTAssertTrue(ChatEffects.isCelebration("🎉"))
        XCTAssertTrue(ChatEffects.isCelebration("We shipped it 🥳🥳"))
        XCTAssertFalse(ChatEffects.isCelebration("Happy birthday"))
        XCTAssertFalse(ChatEffects.isCelebration("👍"))
        XCTAssertFalse(ChatEffects.isCelebration(""))
        XCTAssertFalse(ChatEffects.isCelebration(nil))
    }
}
