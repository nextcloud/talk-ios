//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitSmartRepliesTest: XCTestCase {

    func testSuggestedRepliesAreOnlyShownForMessagesFromOthers() {
        let other = SmartReplies.ContextMessage(author: "Bob", isOwnMessage: false, text: "Lunch today?")
        let own = SmartReplies.ContextMessage(author: "Alice", isOwnMessage: true, text: "Sure")
        let empty = SmartReplies.ContextMessage(author: "Bob", isOwnMessage: false, text: "  ")

        XCTAssertTrue(SmartReplies.shouldSuggestReplies(to: [other]))
        XCTAssertTrue(SmartReplies.shouldSuggestReplies(to: [own, other]))
        XCTAssertFalse(SmartReplies.shouldSuggestReplies(to: [other, own]))
        XCTAssertFalse(SmartReplies.shouldSuggestReplies(to: [empty]))
        XCTAssertFalse(SmartReplies.shouldSuggestReplies(to: []))
    }

    func testSuggestedRepliesPrompt() {
        var messages = (1...10).map { SmartReplies.ContextMessage(author: "Bob", isOwnMessage: false, text: "Message \($0)") }
        messages.append(SmartReplies.ContextMessage(author: "Alice", isOwnMessage: true, text: "Line 1\nLine 2"))

        let prompt = SmartReplies.prompt(for: messages)

        // Only the last messages are used, and the own ones are called "Me"
        XCTAssertFalse(prompt.contains("Message 3\n"))
        XCTAssertTrue(prompt.contains("Bob: Message 10"))
        XCTAssertTrue(prompt.contains("Me: Line 1 Line 2"))
        XCTAssertFalse(prompt.contains("Alice"))
    }

    func testSuggestedRepliesAreCleanedUp() {
        let longReply = String(repeating: "a", count: SmartReplies.maxReplyLength + 1)

        XCTAssertEqual(SmartReplies.cleaned(["  Sure!  ", "\"Sounds good\"", "sure!", "", longReply, "See you", "Later"]),
                       ["Sure!", "Sounds good", "See you"])
    }
}
