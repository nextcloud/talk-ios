//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitInteractiveWidgetsTest: XCTestCase {

    func testMarkingAsReadInWidgetData() {
        let unreadMention = ConversationsWidgetData.Conversation(id: "1", token: "t1", displayName: "Design", unreadMessages: 3, unreadMention: true,
                                                                 isFavorite: true, hasCall: false, avatarFileName: "a.png")
        let unread = ConversationsWidgetData.Conversation(id: "2", token: "t2", displayName: "Bob", unreadMessages: 1, unreadMention: false,
                                                          isFavorite: false, hasCall: true, avatarFileName: nil)
        let data = ConversationsWidgetData(server: "https://cloud.example.com", userId: "alice", conversations: [unreadMention, unread],
                                           unreadConversations: 2, unreadMentions: 1)

        let markedAsRead = data.markingAsRead(token: "t1")

        XCTAssertEqual(markedAsRead.conversations[0].unreadMessages, 0)
        XCTAssertFalse(markedAsRead.conversations[0].unreadMention)
        XCTAssertEqual(markedAsRead.conversations[0].avatarFileName, "a.png")
        XCTAssertEqual(markedAsRead.conversations[1], unread)
        XCTAssertEqual(markedAsRead.unreadConversations, 1)
        XCTAssertEqual(markedAsRead.unreadMentions, 0)

        // Already read or unknown conversations change nothing
        XCTAssertEqual(markedAsRead.markingAsRead(token: "t1"), markedAsRead)
        XCTAssertEqual(data.markingAsRead(token: "unknown"), data)
    }

    func testControlsStateRoundTrip() {
        let suiteName = "UnitSystemIntegrationTest"
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(TalkControlsState.load(appGroupIdentifier: suiteName), TalkControlsState())

        let state = TalkControlsState(isInCall: true, isMicrophoneMuted: true, userStatus: "dnd")
        state.save(appGroupIdentifier: suiteName)

        XCTAssertEqual(TalkControlsState.load(appGroupIdentifier: suiteName), state)

        TalkControlsState.remove(appGroupIdentifier: suiteName)

        XCTAssertEqual(TalkControlsState.load(appGroupIdentifier: suiteName), TalkControlsState())
    }
}
