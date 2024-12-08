//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitNCChatMessageTest: TestBaseRealm {

    func testUnreadMessageSeparatorUrlCheck() throws {
        let message = NCChatMessage()
        message.messageId = MessageSeparatorTableViewCell.unreadMessagesSeparatorId

        updateCapabilities { cap in
            cap.referenceApiSupported = true
        }

        XCTAssertFalse(message.containsURL())
    }

    func testMentionRendering() throws {
        let mentionParameters = """
        {
            "mention-user1": {
                "type": "user",
                "id": "username@nextcloud.invalid",
                "name": "Username with space",
                "server": "https://nextcloud.invalid"
            }
        }
        """

        let mentionMessage = NCChatMessage()
        mentionMessage.messageParametersJSONString = mentionParameters

        mentionMessage.message = "{mention-user1}"
        XCTAssertEqual(mentionMessage.parsedMarkdownForChat().string, "@Username with space")

        mentionMessage.message = "{\n{mention-user1}"
        XCTAssertEqual(mentionMessage.parsedMarkdownForChat().string, "{\n@Username with space")

        mentionMessage.message = "@{mention-user1}"
        XCTAssertEqual(mentionMessage.parsedMarkdownForChat().string, "@@Username with space")

        mentionMessage.message = " abc{mention-user1}abc "
        XCTAssertEqual(mentionMessage.parsedMarkdownForChat().string, " abc@Username with spaceabc ")

        mentionMessage.message = "{mention-user1}{mention-user2}"
        XCTAssertEqual(mentionMessage.parsedMarkdownForChat().string, "@Username with space{mention-user2}")
    }

}
