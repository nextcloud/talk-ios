//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitTypingIndicatorView: XCTestCase {

    func testMentionIdFromServerLocal() throws {
        let typingView = TypingIndicatorView()

        XCTAssertEqual(typingView.typingLabel.text, "")

        typingView.addTyping(userIdentifier: "alice", displayName: "alice")
        XCTAssertEqual(typingView.typingLabel.text, "alice is typing…")

        typingView.addTyping(userIdentifier: "bob", displayName: "bob")
        typingView.updateTypingIndicator()
        XCTAssertEqual(typingView.typingLabel.text, "alice and bob are typing…")

        typingView.addTyping(userIdentifier: "charlie", displayName: "charlie")
        typingView.updateTypingIndicator()
        XCTAssertEqual(typingView.typingLabel.text, "alice, bob and charlie are typing…")

        typingView.addTyping(userIdentifier: "user1", displayName: "user1")
        typingView.updateTypingIndicator()
        XCTAssertEqual(typingView.typingLabel.text, "alice, bob, charlie and 1 other is typing…")

        typingView.addTyping(userIdentifier: "user2", displayName: "user2")
        typingView.updateTypingIndicator()
        XCTAssertEqual(typingView.typingLabel.text, "alice, bob, charlie and 2 others are typing…")
    }
}
