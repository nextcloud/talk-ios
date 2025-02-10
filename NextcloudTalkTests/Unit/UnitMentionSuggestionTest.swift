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

        XCTAssertEqual(suggestion.source, "users")

        XCTAssertEqual(suggestion.mention.id, "my-id")
        XCTAssertEqual(suggestion.mention.label, "My Label")
        XCTAssertEqual(suggestion.mention.idForChat, "@\"my-id\"")
        XCTAssertEqual(suggestion.mention.labelForChat, "@My Label")
    }

    func testLocalGuestMention() throws {
        let data = [
            "id": "guest/guest-id"
        ]

        let suggestion = MentionSuggestion(dictionary: data)

        XCTAssertEqual(suggestion.mention.id, "guest/guest-id")
        XCTAssertEqual(suggestion.mention.idForChat, "@\"guest/guest-id\"")
    }

    func testLocalWhitespaceMention() throws {
        let data = [
            "id": "my id"
        ]

        let suggestion = MentionSuggestion(dictionary: data)

        XCTAssertEqual(suggestion.mention.id, "my id")
        XCTAssertEqual(suggestion.mention.idForChat, "@\"my id\"")
    }

    func testMentionId() throws {
        let data = [
            "id": "my-id",
            "mentionId": "mention-id"
        ]

        let suggestion = MentionSuggestion(dictionary: data)

        XCTAssertEqual(suggestion.mention.id, "my-id")
        XCTAssertEqual(suggestion.mention.mentionId, "mention-id")
        XCTAssertEqual(suggestion.mention.idForChat, "@\"mention-id\"")
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
        XCTAssertEqual(parameter.mention?.label, "My Label")
        XCTAssertEqual(parameter.mention?.mentionId, "mention-id")
        XCTAssertEqual(parameter.mention?.idForChat, "@\"mention-id\"")
        XCTAssertEqual(parameter.mention?.labelForChat, "@My Label")
        XCTAssertEqual(parameter.type, "user")
    }
}
