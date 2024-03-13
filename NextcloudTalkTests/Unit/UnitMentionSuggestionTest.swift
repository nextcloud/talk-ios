//
// Copyright (c) 2024 Marcel Müller <marcel-mueller@gmx.de>
//
// Author Marcel Müller <marcel-mueller@gmx.de>
//
// GNU GPL version 3 or any later version
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
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
