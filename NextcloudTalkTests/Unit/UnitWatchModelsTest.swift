//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitWatchModelsTest: XCTestCase {

    func testWatchModelsRoundTrip() throws {
        let snapshot = WatchSnapshot(accountName: "Alice (cloud.example.com)", conversations: [
            WatchConversation(token: "t1", displayName: "Design", lastMessage: "Bob: Hi", lastActivity: Date(timeIntervalSince1970: 1000),
                              unreadMessages: 2, unreadMention: true, hasCall: false, isFavorite: true, isOneToOne: false, canReact: true)
        ])
        let messages = [
            WatchMessage(id: 1, author: "Bob", text: "Hi 👋", date: Date(timeIntervalSince1970: 2000), isOwnMessage: false,
                         reactions: [WatchReaction(reaction: "👍", count: 2, reactedBySelf: true)])
        ]

        XCTAssertEqual(WatchRequest.decode(WatchSnapshot.self, from: WatchRequest.encode(snapshot)), snapshot)
        XCTAssertEqual(WatchRequest.decode([WatchMessage].self, from: WatchRequest.encode(messages)), messages)
        XCTAssertNil(WatchRequest.decode(WatchSnapshot.self, from: nil))
        XCTAssertNil(WatchRequest.decode(WatchSnapshot.self, from: Data("garbage".utf8)))
    }
}
