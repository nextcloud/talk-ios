//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitConversationHandoffTest: XCTestCase {

    func testHandoffWebURL() {
        XCTAssertEqual(ConversationHandoff.webURL(server: "https://cloud.example.com", token: "abc123")?.absoluteString,
                       "https://cloud.example.com/index.php/call/abc123")
        XCTAssertEqual(ConversationHandoff.webURL(server: "https://cloud.example.com/sub/", token: "abc123")?.absoluteString,
                       "https://cloud.example.com/sub/index.php/call/abc123")
        XCTAssertNil(ConversationHandoff.webURL(server: "https://cloud.example.com", token: nil))
        XCTAssertNil(ConversationHandoff.webURL(server: "https://cloud.example.com", token: ""))
    }

    func testHandoffActivityRoundTrip() throws {
        let account = TalkAccount()
        account.server = "https://cloud.example.com"
        account.userId = "alice"

        let room = NCRoom()
        room.token = "abc123"
        room.displayName = "Secret project"
        room.isSensitive = true

        let activity = ConversationHandoff.userActivity(for: room, account: account)

        XCTAssertTrue(activity.isEligibleForHandoff)
        XCTAssertFalse(activity.isEligibleForSearch)
        // The name of a sensitive conversation is not shown on the other device
        XCTAssertNotEqual(activity.title, "Secret project")

        let components = try XCTUnwrap(ConversationHandoff.conversationURL(for: activity))
        let queryItems = (components.queryItems ?? []) as NSArray

        XCTAssertEqual(components.host, "open-conversation")
        XCTAssertEqual(NCUtils.value(forKey: "server", fromQueryItems: queryItems), "https://cloud.example.com")
        XCTAssertEqual(NCUtils.value(forKey: "user", fromQueryItems: queryItems), "alice")
        XCTAssertEqual(NCUtils.value(forKey: "withRoomToken", fromQueryItems: queryItems), "abc123")

        // Other activities are ignored
        XCTAssertNil(ConversationHandoff.conversationURL(for: NSUserActivity(activityType: "com.example.other")))
    }
}
