//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
@testable import NextcloudTalk

@MainActor
struct UnitTypingIndicatorView {

    @Test func `typing indicator label`() throws {
        let typingView = TypingIndicatorView()

        #expect(typingView.typingLabel.text?.isEmpty == true)

        typingView.addTyping(userIdentifier: "alice", displayName: "alice")
        #expect(typingView.typingLabel.text == "alice is typing…")

        typingView.addTyping(userIdentifier: "bob", displayName: "bob")
        typingView.updateTypingIndicator()
        #expect(typingView.typingLabel.text == "alice and bob are typing…")

        typingView.addTyping(userIdentifier: "charlie", displayName: "charlie")
        typingView.updateTypingIndicator()
        #expect(typingView.typingLabel.text == "alice, bob and charlie are typing…")

        typingView.addTyping(userIdentifier: "user1", displayName: "user1")
        typingView.updateTypingIndicator()
        #expect(typingView.typingLabel.text == "alice, bob, charlie and 1 other is typing…")

        typingView.addTyping(userIdentifier: "user2", displayName: "user2")
        typingView.updateTypingIndicator()
        #expect(typingView.typingLabel.text == "alice, bob, charlie and 2 others are typing…")
    }
}
