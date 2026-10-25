//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitEmojiAnimationTest: XCTestCase {

    @MainActor
    func testEmojiAnimations() {
        XCTAssertEqual(ChatEffects.emojiAnimation(forEmojiMessage: "❤️"), .heartbeat)
        XCTAssertEqual(ChatEffects.emojiAnimation(forEmojiMessage: "🥰🥰"), .heartbeat)
        XCTAssertEqual(ChatEffects.emojiAnimation(forEmojiMessage: "😂"), .shake)
        XCTAssertEqual(ChatEffects.emojiAnimation(forEmojiMessage: "👍"), .bounce)
        // Skin tones are animated like the emoji itself
        XCTAssertEqual(ChatEffects.emojiAnimation(forEmojiMessage: "👍🏽"), .bounce)
        XCTAssertEqual(ChatEffects.emojiAnimation(forEmojiMessage: "👋🏻"), .wave)
        XCTAssertEqual(ChatEffects.emojiAnimation(forEmojiMessage: "🔥"), .flicker)
        XCTAssertEqual(ChatEffects.emojiAnimation(forEmojiMessage: "🌍"), .spin)
        XCTAssertEqual(ChatEffects.emojiAnimation(forEmojiMessage: "🐱"), .pop)
        XCTAssertEqual(ChatEffects.emojiAnimation(forEmojiMessage: ""), .pop)
    }
}
