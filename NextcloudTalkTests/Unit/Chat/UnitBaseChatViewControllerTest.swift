//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Testing
@testable import NextcloudTalk

@Suite(.serialized)
final class UnitBaseChatViewControllerTest: TestBaseRealm {

    // Initialized in `init` because they depend on the active account created by the base class setup.
    private var baseController: BaseChatViewController!
    private var testMessage: NCChatMessage!

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

    override init() {
        super.init()

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        baseController = BaseChatViewController(forRoom: NCRoom(), withAccount: activeAccount)!
        testMessage = NCChatMessage(dictionary: [:], andAccountId: activeAccount.accountId)
    }

    @Test func `system message cell height`() throws {
        testMessage.message = "System Message"
        testMessage.systemMessage = "test_system_message"
        #expect(baseController.getCellHeight(for: testMessage, with: 300) == 35.0)
    }

    @Test func `cell height`() throws {
        // Normal chat message
        testMessage.message = "test"
        testMessage.messageId = 1
        #expect(baseController.getCellHeight(for: testMessage, with: 300) == 101.0)

        // Multiline chat message
        testMessage.message = "test\nasd\nasd"
        testMessage.messageId = 2
        #expect(baseController.getCellHeight(for: testMessage, with: 300) == 141.0)

        // Normal chat message with reaction
        testMessage.message = "test"
        testMessage.messageId = 3
        testMessage.setOrUpdateTemporaryReaction("👍", state: .added)
        #expect(baseController.getCellHeight(for: testMessage, with: 300) == 141.0)
    }

    @Test func `grouped cell height`() throws {
        // Grouped chat message
        testMessage.message = "test"
        testMessage.isGroupMessage = true
        testMessage.messageId = 1
        #expect(baseController.getCellHeight(for: testMessage, with: 300) == 71.0)

        // Grouped chat message with reaction
        testMessage.messageId = 2
        testMessage.setOrUpdateTemporaryReaction("👍", state: .added)
        #expect(baseController.getCellHeight(for: testMessage, with: 300) == 111.0)
    }

    @Test func `grouped cell with quote height`() throws {
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
        #expect(baseController.getCellHeight(for: testMessage, with: 300) == 171.0)
    }

    @Test func `cell with URL height`() throws {
        // Chat message with URL preview
        testMessage.message = "test - https://nextcloud.com"
        testMessage.messageId = 1

        updateCapabilities { cap in
            cap.referenceApiSupported = true
        }

        #expect(baseController.getCellHeight(for: testMessage, with: 300) == 206.0)

        // Test URL with grouped message
        testMessage.isGroupMessage = true
        testMessage.messageId = 2
        #expect(baseController.getCellHeight(for: testMessage, with: 300) == 176.0)
    }

    @Test func `cell with poll height`() throws {
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
        #expect(baseController.getCellHeight(for: testMessage, with: 300) == 119.0)
    }

    @Test func `cell with geolocation height`() {
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
        #expect(baseController.getCellHeight(for: testMessage, with: 300) == 231.0)
    }

    @Test func `cell with file height`() {
        // Test without file caption
        testMessage.messageParametersJSONString = fileMessageParameters
        testMessage.message = "{file}"
        #expect(baseController.getCellHeight(for: testMessage, with: 300) == 221.0)
    }

    @Test func `cell with file caption height`() {
        testMessage.messageParametersJSONString = fileMessageParameters
        testMessage.message = "File caption..."
        #expect(baseController.getCellHeight(for: testMessage, with: 300) == 241.0)
    }

    @Test func `cell with file caption URL height`() {
        updateCapabilities { cap in
            cap.referenceApiSupported = true
        }

        testMessage.messageParametersJSONString = fileMessageParameters
        testMessage.message = "File caption... https://nextcloud.com"
        #expect(baseController.getCellHeight(for: testMessage, with: 300) == 366.0)
    }

    @Test func `cell with file and quote height`() {
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
        #expect(baseController.getCellHeight(for: testMessage, with: 300) == 311.0)
    }

    @Test func `cell with voice message height`() {
        testMessage.message = "abc"
        testMessage.messageType = "voice-message"
        #expect(baseController.getCellHeight(for: testMessage, with: 300) == 133.0)
    }

    @Test func `cell with quote height`() throws {
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
        #expect(baseController.getCellHeight(for: testMessage, with: 300) == 171.0)
    }

}
