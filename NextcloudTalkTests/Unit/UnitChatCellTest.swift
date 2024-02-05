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

final class UnitChatCellTest: TestBaseRealm {

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

        baseController = BaseChatViewController(for: NCRoom())!
        testMessage = NCChatMessage()
    }

    func testInvisibleCellHeight() throws {
        // Empty message should have a height of 0
        testMessage.message = ""
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 0.0)

        // Test update message
        testMessage.message = "System Message"
        testMessage.systemMessage = "message_deleted"
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 0.0)
    }

    func testSystemMessageCellHeight() throws {
        testMessage.message = "System Message"
        testMessage.systemMessage = "test_system_message"
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 30.0)
    }

    func testCellHeight() throws {
        // Normal chat message
        testMessage.message = "test"
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 70.0)

        // Multiline chat message
        testMessage.message = "test\nasd\nasd"
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 108.0)

        // Normal chat message with reaction
        testMessage.message = "test"
        testMessage.addTemporaryReaction("👍")
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 110.0)
    }

    func testGroupedCellHeight() throws {
        // Grouped chat message
        testMessage.message = "test"
        testMessage.isGroupMessage = true
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 30.0)

        // Grouped chat message with reaction
        testMessage.addTemporaryReaction("👍")
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 70.0)
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
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 135.0)
    }

    func testCellWithUrlHeight() throws {
        // Chat message with URL preview
        testMessage.message = "test - https://nextcloud.com"

        updateCapabilities { cap in
            cap.referenceApiSupported = true
        }

        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 175.0)

        // Test URL with grouped message
        testMessage.isGroupMessage = true
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 135.0)
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
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 90.0)
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
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 200.0)
    }

    func testCellWithFileHeight() {
        // Test without file caption
        testMessage.messageParametersJSONString = fileMessageParameters
        testMessage.message = "{file}"
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 190.0)
    }

    func testCellWithFileCaptionHeight() {
        testMessage.messageParametersJSONString = fileMessageParameters
        testMessage.message = "File caption..."
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 210.0)
    }

    func testCellWithFileCaptionUrlHeight() {
        updateCapabilities { cap in
            cap.referenceApiSupported = true
        }

        testMessage.messageParametersJSONString = fileMessageParameters
        testMessage.message = "File caption... https://nextcloud.com"
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 210.0)
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
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 210.0)

        // This should be 275 if the file cell would be able to display a quoted view
        // XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 275.0)
    }

    func testCellWithVoiceMessageHeight() {
        testMessage.message = "abc"
        testMessage.messageType = "voice-message"
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 104.0)
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
        XCTAssertEqual(baseController.getCellHeight(for: testMessage, with: 300), 135.0)
    }

}
