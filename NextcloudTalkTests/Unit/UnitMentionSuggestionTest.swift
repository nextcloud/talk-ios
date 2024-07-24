//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitMentionSuggestionTest: XCTestCase {

    func testLocalMention() throws {
        let data = [
            "id": "my-id",
            "label": "My Label",
            "source": "users"
        ]

        let suggestion = MentionSuggestion(dictionary: data)

        XCTAssertEqual(suggestion.id, "my-id")
        XCTAssertEqual(suggestion.label, "My Label")
        XCTAssertEqual(suggestion.source, "users")
        XCTAssertEqual(suggestion.getIdForChat(), "my-id")
        XCTAssertEqual(suggestion.getIdForAvatar(), "my-id")
    }

    func testLocalGuestMention() throws {
        let data = [
            "id": "guest/guest-id"
        ]

        let suggestion = MentionSuggestion(dictionary: data)

        XCTAssertEqual(suggestion.id, "guest/guest-id")
        XCTAssertEqual(suggestion.getIdForChat(), "\"guest/guest-id\"")
        XCTAssertEqual(suggestion.getIdForAvatar(), "guest/guest-id")
    }

    func testLocalWhitespaceMention() throws {
        let data = [
            "id": "my id"
        ]

        let suggestion = MentionSuggestion(dictionary: data)

        XCTAssertEqual(suggestion.id, "my id")
        XCTAssertEqual(suggestion.getIdForChat(), "\"my id\"")
        XCTAssertEqual(suggestion.getIdForAvatar(), "my id")
    }

    func testMentionId() throws {
        let data = [
            "id": "my-id",
            "mentionId": "mention-id"
        ]

        let suggestion = MentionSuggestion(dictionary: data)

        XCTAssertEqual(suggestion.id, "my-id")
        XCTAssertEqual(suggestion.mentionId, "mention-id")
        XCTAssertEqual(suggestion.getIdForChat(), "mention-id")
        XCTAssertEqual(suggestion.getIdForAvatar(), "my-id")
    }

    func testMessageParameter() throws {
        let data = [
            "id": "my-id",
            "mentionId": "mention-id",
            "label": "My Label",
            "source": "users"
        ]

        let suggestion = MentionSuggestion(dictionary: data)
        let parameter = suggestion.asMessageParameter()

        XCTAssertEqual(parameter.parameterId, "my-id")
        XCTAssertEqual(parameter.name, "My Label")
        XCTAssertEqual(parameter.mentionDisplayName, "@My Label")
        XCTAssertEqual(parameter.mentionId, "@mention-id")
        XCTAssertEqual(parameter.type, "user")
    }
}
