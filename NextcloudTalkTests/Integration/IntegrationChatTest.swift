//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
import Foundation
@testable import NextcloudTalk

final class IntegrationChatTest: TestBase {

    func testSendMessage() async throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let chatMessage = "Test Message 😀😆"

        let room = try await createUniqueRoom(prefix: "Integration Test Room 👍", withAccount: activeAccount)
        let message = try await sendMessage(message: chatMessage, inRoom: room.token, withAccount: activeAccount)

        XCTAssertNotNil(message)
        XCTAssertEqual(message.message, chatMessage)
        XCTAssertEqual(message.token, room.token)
    }

    func testPinMessage() async throws {
        try skipWithoutCapability(capability: kCapabilityPinnedMessages)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let chatMessage = "Test Message 😀😆"

        let room = try await createUniqueRoom(prefix: "Pin message room", withAccount: activeAccount)
        let message = try await sendMessage(message: chatMessage, inRoom: room.token, withAccount: activeAccount)

        // Pin message
        _ = try await NCAPIController.sharedInstance().pinMessage(message.messageId, inRoom: room.token, pinUntil: 0, forAccount: activeAccount)
        var updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        XCTAssertEqual(try XCTUnwrap(updatedRoom).lastPinnedId, message.messageId)

        _ = try await NCAPIController.sharedInstance().unpinMessageForSelf(message.messageId, inRoom: room.token, forAccount: activeAccount)
        updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        XCTAssertEqual(try XCTUnwrap(updatedRoom).lastPinnedId, message.messageId)
        XCTAssertEqual(try XCTUnwrap(updatedRoom).hiddenPinnedId, message.messageId)

        _ = try await NCAPIController.sharedInstance().unpinMessage(message.messageId, inRoom: room.token, forAccount: activeAccount)
        updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        XCTAssertEqual(try XCTUnwrap(updatedRoom).lastPinnedId, 0)
    }

}
