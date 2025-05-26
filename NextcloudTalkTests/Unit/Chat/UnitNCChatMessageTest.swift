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

    func testMentionParameters() throws {
        let messageParameters = """
        {
            "actor": {
                "type": "user",
                "id": "admin",
                "name": "admin ABC",
                "mention-id": "admin"
            },
            "mention-federated-user1": {
                "type": "user",
                "id": "user1",
                "name": "User1 Displayname",
                "server": "https://nextcloud.local",
                "mention-id": "federated_user/user1@nextcloud.local"
            },
            "mention-user1": {
                "type": "user",
                "id": "alice",
                "name": "alice",
                "mention-id": "alice"
            },
            "mention-call1": {
                "type": "call",
                "id": "12345",
                "name": "Group Conversation",
                "call-type": "public",
                "icon-url": "https://nextcloud.local/ocs/v2.php/apps/spreed/api/v1/room/12345/avatar?v=1b893bde",
                "mention-id": "all"
            }
        }
        """

        let message = NCChatMessage()
        message.messageParametersJSONString = messageParameters

        message.message = "Hello {mention-user1} --- hello {mention-federated-user1} --- hello {mention-call1} 123"
        XCTAssertEqual(message.parsedMarkdownForChat().string, "Hello @alice --- hello @User1 Displayname --- hello @Group Conversation 123")

        let mentionsDict = message.mentionMessageParameters
        XCTAssertEqual(mentionsDict.count, 3)

        let userMention = mentionsDict.first(where: { $0.value.type == "user" && !$0.key.contains("federated") })!.value
        XCTAssertEqual(userMention.mention?.mentionId, "alice")

        let federatedMention = mentionsDict.first(where: { $0.value.type == "user" && $0.key.contains("federated") })!.value
        XCTAssertEqual(federatedMention.mention?.mentionId, "federated_user/user1@nextcloud.local")

        let callMention = mentionsDict.first(where: { $0.value.type == "call" })!.value
        XCTAssertEqual(callMention.mention?.mentionId, "all")

        XCTAssertEqual(message.sendingMessage, "Hello @\"alice\" --- hello @\"federated_user/user1@nextcloud.local\" --- hello @\"all\" 123")
        XCTAssertEqual(message.sendingMessageWithDisplayNames, "Hello @alice --- hello @User1 Displayname --- hello @Group Conversation 123")
    }

    func testLastMessageFileUpdate() throws {
        let fileMessageParameters = """
        {
            "actor": {
                "type": "user",
                "id": "admin",
                "name": "admin"
            },
            "file": {
                "type": "file",
                "id": "9",
                "name": "photo-1517603250781-c4eac1449a80.jpeg",
                "size": 444676,
                "path": "Media/photo-1517603250781-c4eac1449a80.jpeg",
                "link": "https://nextcloud-mm.local/index.php/f/9",
                "etag": "60fb4ececc370787b1cdc5623ff4a189",
                "permissions": 27,
                "mimetype": "image/jpeg",
                "preview-available": "yes",
                "width": 1491,
                "height": 837
            }
        }
        """

        let newFileMessageParameters = """
        {
            "actor": {
                "type": "user",
                "id": "bob",
                "name": "bob"
            },
            "file": {
                "type": "file",
                "id": "9",
                "name": "abc.jpeg",
                "size": 444676,
                "path": "abc.jpeg",
                "link": "https://nextcloud-mm.local/index.php/f/9",
                "etag": "60fb4ececc370787b1cdc5623ff4a189",
                "permissions": 27,
                "mimetype": "image/jpeg",
                "preview-available": "yes",
                "width": 1491,
                "height": 837
            }
        }
        """

        let existingMessage = NCChatMessage()
        existingMessage.messageId = 1
        existingMessage.internalId = "internal-1"
        existingMessage.message = "existing"
        existingMessage.messageParametersJSONString = fileMessageParameters

        let updateMessage = NCChatMessage()
        updateMessage.messageId = 1
        updateMessage.internalId = "internal-1"
        updateMessage.message = "new"
        updateMessage.messageParametersJSONString = newFileMessageParameters

        NCChatMessage.update(existingMessage, with: updateMessage, isRoomLastMessage: true)
        XCTAssertEqual(existingMessage.message, "new")
        XCTAssertEqual(existingMessage.file().path, "Media/photo-1517603250781-c4eac1449a80.jpeg")

        let parameters = (existingMessage.messageParameters as? [String: Any])?["actor"] as? [String: String]
        XCTAssertEqual(try XCTUnwrap(parameters)["name"], "bob")
    }
}
