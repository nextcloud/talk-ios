//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitBaseChatViewControllerTest: TestBaseRealm {

    var baseController: BaseChatViewController!
    var testMessage: NCChatMessage!

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

    override func setUpWithError() throws {
        try super.setUpWithError()

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        baseController = BaseChatViewController(forRoom: NCRoom(), withAccount: activeAccount)!
        testMessage = NCChatMessage(dictionary: [:], andAccountId: activeAccount.accountId)
    }

    func testSystemMessageCellHeight() throws {
        testMessage.message = "System Message"
        testMessage.systemMessage = "test_system_message"
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 35.0)
    }

    func testCellHeight() throws {
        // Normal chat message
        testMessage.message = "test"
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 96.0)

        // Multiline chat message
        testMessage.message = "test\nasd\nasd"
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 136.0)

        // Normal chat message with reaction
        testMessage.message = "test"
        testMessage.setOrUpdateTemporaryReaction("👍", state: .added)
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 136.0)
    }

    func testGroupedCellHeight() throws {
        // Grouped chat message
        testMessage.message = "test"
        testMessage.isGroupMessage = true
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 71.0)

        // Grouped chat message with reaction
        testMessage.setOrUpdateTemporaryReaction("👍", state: .added)
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 111.0)
    }

    func testGroupedCellWithQuoteHeight() throws {
        // Add an existing message to the database
        let existingMessage = NCChatMessage()
        existingMessage.messageId = 1
        existingMessage.internalId = "internal-1"
        existingMessage.message = "existing"

        try? realm.transaction {
            realm.add(existingMessage)
        }

        // Chat message with a quote
        testMessage.message = "test"
        testMessage.parentId = "internal-1"
        testMessage.isGroupMessage = true
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 166.0)
    }

    func testCellWithUrlHeight() throws {
        // Chat message with URL preview
        testMessage.message = "test - https://nextcloud.com"

        updateCapabilities { cap in
            cap.referenceApiSupported = true
        }

        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 201.0)

        // Test URL with grouped message
        testMessage.isGroupMessage = true
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 176.0)
    }

    func testCellWithPollHeight() throws {
        testMessage.messageParametersJSONString = """
{
    "actor": {
        "type": "user",
        "id": "admin",
        "name": "admin"
    },
    "object": {
        "type": "talk-poll",
        "id": "1",
        "name": "Test"
    }
}
"""

        testMessage.message = "{object}"
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 114.0)
    }

    func testCellWithGeolocationHeight() {
        testMessage.messageParametersJSONString = """
{
  "actor": {
    "type": "user",
    "id": "admin",
    "name": "admin"
  },
  "object": {
    "name": "Geteilter Ort",
    "longitude": "6.764340827050928",
    "latitude": "53.20406320313201",
    "type": "geo-location",
    "id": "geo:53.20406320313201,6.764340827050928",
    "icon-url": "https://nextcloud-mm.local/ocs/v2.php/apps/spreed/api/v1/room/2yjsf6i6/avatar?v=02234d2d"
  }
}
"""

        testMessage.message = "{object}"
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 226.0)
    }

    func testCellWithFileHeight() {
        // Test without file caption
        testMessage.messageParametersJSONString = fileMessageParameters
        testMessage.message = "{file}"
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 216.0)
    }

    func testCellWithFileCaptionHeight() {
        testMessage.messageParametersJSONString = fileMessageParameters
        testMessage.message = "File caption..."
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 236.0)
    }

    func testCellWithFileCaptionUrlHeight() {
        updateCapabilities { cap in
            cap.referenceApiSupported = true
        }

        testMessage.messageParametersJSONString = fileMessageParameters
        testMessage.message = "File caption... https://nextcloud.com"
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 361.0)
    }

    func testCellWithFileAndQuoteHeight() {
        testMessage.messageParametersJSONString = fileMessageParameters
        testMessage.message = "File caption..."

        // Add an existing message to the database
        let existingMessage = NCChatMessage()
        existingMessage.messageId = 1
        existingMessage.internalId = "internal-1"
        existingMessage.message = "existing"

        try? realm.transaction {
            realm.add(existingMessage)
        }

        testMessage.parentId = "internal-1"
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 306.0)
    }

    func testCellWithVoiceMessageHeight() {
        testMessage.message = "abc"
        testMessage.messageType = "voice-message"
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 128.0)
    }

    func testCellWithQuoteHeight() throws {
        // Add an existing message to the database
        let existingMessage = NCChatMessage()
        existingMessage.messageId = 1
        existingMessage.internalId = "internal-1"
        existingMessage.message = "existing"

        try? realm.transaction {
            realm.add(existingMessage)
        }

        // Chat message with a quote
        testMessage.message = "test"
        testMessage.parentId = "internal-1"
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 166.0)
    }

}
