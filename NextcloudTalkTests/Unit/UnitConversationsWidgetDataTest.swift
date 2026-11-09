//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitConversationsWidgetDataTest: XCTestCase {

    private let conversation = ConversationsWidgetData.Conversation(id: "account@token", token: "abc123", displayName: "Design & Dev",
                                                                    unreadMessages: 2, unreadMention: true, isFavorite: true,
                                                                    hasCall: false, avatarFileName: nil)

    func testOpenURL() throws {
        let data = ConversationsWidgetData(server: "https://cloud.example.com/sub", userId: "alice smith", conversations: [conversation],
                                           unreadConversations: 1, unreadMentions: 1)

        let url = try XCTUnwrap(data.openURL(for: conversation))
        let components = try XCTUnwrap(NSURLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = (components.queryItems ?? []) as NSArray

        XCTAssertEqual(components.scheme, "nextcloudtalk")
        XCTAssertEqual(components.host, "open-conversation")
        XCTAssertEqual(NCUtils.value(forKey: "server", fromQueryItems: queryItems), "https://cloud.example.com/sub")
        XCTAssertEqual(NCUtils.value(forKey: "user", fromQueryItems: queryItems), "alice smith")
        XCTAssertEqual(NCUtils.value(forKey: "withRoomToken", fromQueryItems: queryItems), "abc123")
    }

    func testCodableRoundTrip() throws {
        let data = ConversationsWidgetData(server: "https://cloud.example.com", userId: "alice", conversations: [conversation],
                                           unreadConversations: 1, unreadMentions: 1)

        let decoded = try JSONDecoder().decode(ConversationsWidgetData.self, from: JSONEncoder().encode(data))

        XCTAssertEqual(decoded, data)
    }
}
