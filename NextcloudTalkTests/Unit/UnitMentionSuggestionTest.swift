//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
@testable import NextcloudTalk

struct UnitMentionSuggestionTest {

    @Test func `local mention`() throws {
        let data = [
            "id": "my-id",
            "label": "My Label",
            "source": "users"
        ]

        let suggestion = MentionSuggestion(dictionary: data)

        #expect(suggestion.source == "users")

        #expect(suggestion.mention.id == "my-id")
        #expect(suggestion.mention.label == "My Label")
        #expect(suggestion.mention.idForChat == "@\"my-id\"")
        #expect(suggestion.mention.labelForChat == "@My Label")
    }

    @Test func `local guest mention`() throws {
        let data = [
            "id": "guest/guest-id"
        ]

        let suggestion = MentionSuggestion(dictionary: data)

        #expect(suggestion.mention.id == "guest/guest-id")
        #expect(suggestion.mention.idForChat == "@\"guest/guest-id\"")
    }

    @Test func `local whitespace mention`() throws {
        let data = [
            "id": "my id"
        ]

        let suggestion = MentionSuggestion(dictionary: data)

        #expect(suggestion.mention.id == "my id")
        #expect(suggestion.mention.idForChat == "@\"my id\"")
    }

    @Test func `mention ID`() throws {
        let data = [
            "id": "my-id",
            "mentionId": "mention-id"
        ]

        let suggestion = MentionSuggestion(dictionary: data)

        #expect(suggestion.mention.id == "my-id")
        #expect(suggestion.mention.mentionId == "mention-id")
        #expect(suggestion.mention.idForChat == "@\"mention-id\"")
    }

    @Test func `message parameter`() throws {
        let data = [
            "id": "my-id",
            "mentionId": "mention-id",
            "label": "My Label",
            "source": "users"
        ]

        let suggestion = MentionSuggestion(dictionary: data)
        let parameter = suggestion.asMessageParameter()

        #expect(parameter.parameterId == "my-id")
        #expect(parameter.name == "My Label")
        #expect(parameter.mention?.label == "My Label")
        #expect(parameter.mention?.mentionId == "mention-id")
        #expect(parameter.mention?.idForChat == "@\"mention-id\"")
        #expect(parameter.mention?.labelForChat == "@My Label")
        #expect(parameter.type == "user")
    }
}
