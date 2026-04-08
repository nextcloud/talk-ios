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
        let (message, details) = try await sendMessage(message: chatMessage, inRoom: room.token, withAccount: activeAccount)

        XCTAssertNotNil(message)
        XCTAssertEqual(message.message, chatMessage)
        XCTAssertEqual(message.token, room.token)
        XCTAssertEqual(details.statusCode, 200)
        XCTAssertGreaterThan(details.lastKnownMessage, 0)

        let exp = expectation(description: "\(#function)\(#line)")

        NCAPIController.sharedInstance().receiveChatMessages(ofRoom: room.token, fromLastMessageId: details.lastKnownMessage, inThread: 0, history: false, includeLastMessage: false, timeout: false, limit: 0, lastCommonReadMessage: 0, setReadMarker: false, markNotificationsAsRead: false, forAccount: activeAccount, completionBlock: { messages, lastKnownMessage, _, error, statusCode in
            XCTAssertNil(messages)
            XCTAssertEqual(lastKnownMessage, -1)
            XCTAssertEqual(statusCode, 304)
            XCTAssertNotNil(error)

            exp.fulfill()
        })

        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)
    }

    func testPinMessage() async throws {
        try skipWithoutCapability(capability: kCapabilityPinnedMessages)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let chatMessage = "Test Message 😀😆"

        let room = try await createUniqueRoom(prefix: "Pin message room", withAccount: activeAccount)
        let (message, _) = try await sendMessage(message: chatMessage, inRoom: room.token, withAccount: activeAccount)

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

    func testScheduleMessages() async throws {
        try skipWithoutCapability(capability: kCapabilityScheduleMessages)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let chatMessage = "Scheduled Message 😀😆"
        let chatMessageEdited = "Scheduled Message 😀😆 Edited"

        let room = try await createUniqueRoom(prefix: "Schedule message room", withAccount: activeAccount)

        // Ensure no message was scheduled in hte room
        var scheduledMessages = try await NCAPIController.sharedInstance().getScheduledMessages(forRoom: room.token, forAccount: activeAccount)
        XCTAssertEqual(scheduledMessages.count, 0)

        // Schedule our first message
        let timestamp = Int(Date().timeIntervalSince1970 + 300)
        var message = try await NCAPIController.sharedInstance().scheduleMessage(chatMessage, inRoom: room.token, sendAt: timestamp, forAccount: activeAccount)
        XCTAssertNotNil(message)

        // Check if we can retrieve the scheduled message
        scheduledMessages = try await NCAPIController.sharedInstance().getScheduledMessages(forRoom: room.token, forAccount: activeAccount)
        XCTAssertEqual(scheduledMessages.count, 1)
        let firstMessage = scheduledMessages.first!
        XCTAssertEqual(firstMessage.message, chatMessage)
        XCTAssertEqual(firstMessage.sendAtTimestamp, timestamp)
        XCTAssertEqual(firstMessage.id, message?.id)

        // Edit the scheduled message
        XCTAssertNotNil(firstMessage.id)
        message = try await NCAPIController.sharedInstance().editScheduledMessage(firstMessage.id, withMessage: chatMessageEdited, inRoom: room.token, sendAt: timestamp, forAccount: activeAccount)

        // Check if we can retrieve the edited scheduled message
        scheduledMessages = try await NCAPIController.sharedInstance().getScheduledMessages(forRoom: room.token, forAccount: activeAccount)
        XCTAssertEqual(scheduledMessages.count, 1)
        XCTAssertEqual(scheduledMessages.first?.message, chatMessageEdited)
        XCTAssertEqual(scheduledMessages.first?.id, message?.id)

        // Delete the scheduled message
        try await NCAPIController.sharedInstance().deleteScheduledMessage(firstMessage.id, inRoom: room.token, forAccount: activeAccount)

        // No scheduled messages should be there anymore
        scheduledMessages = try await NCAPIController.sharedInstance().getScheduledMessages(forRoom: room.token, forAccount: activeAccount)
        XCTAssertEqual(scheduledMessages.count, 0)
    }

    func testMessageReaction() async throws {
        try skipWithoutCapability(capability: kCapabilityReactions)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let chatMessage = "React to message 🥳"

        let room = try await createUniqueRoom(prefix: "Reaction Test Room 🧊", withAccount: activeAccount)
        let (message, _) = try await sendMessage(message: chatMessage, inRoom: room.token, withAccount: activeAccount)

        let exp = expectation(description: "\(#function)\(#line)")

        NCAPIController.sharedInstance().addReaction("👍", toMessage: message.messageId, inRoom: room.token, forAccount: activeAccount) { reactionsDict, error in
            XCTAssertNil(error)
            XCTAssertNotNil(reactionsDict!["👍"])

            NCAPIController.sharedInstance().getReactions(nil, fromMessage: message.messageId, inRoom: room.token, forAccount: activeAccount) { reactionsDict, error in
                XCTAssertNil(error)
                XCTAssertNotNil(reactionsDict!["👍"])

                NCAPIController.sharedInstance().removeReaction("👍", fromMessage: message.messageId, inRoom: room.token, forAccount: activeAccount) { reactionsDict, error in
                    XCTAssertNil(error)
                    XCTAssertNil(reactionsDict!["👍"])

                    NCAPIController.sharedInstance().getReactions(nil, fromMessage: message.messageId, inRoom: room.token, forAccount: activeAccount) { reactionsDict, error in
                        XCTAssertNil(error)
                        XCTAssertNil(reactionsDict!["👍"])

                        exp.fulfill()
                    }
                }
            }
        }

        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)
    }

    func testMessageReminder() async throws {
        try skipWithoutCapability(capability: kCapabilityRemindMeLater)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let chatMessage = "Reminded message"

        let room = try await createUniqueRoom(prefix: "Reminder Test Room", withAccount: activeAccount)
        let (message, _) = try await sendMessage(message: chatMessage, inRoom: room.token, withAccount: activeAccount)

        let exp = expectation(description: "\(#function)\(#line)")
        let timestamp = Int(Date().timeIntervalSince1970)

        NCAPIController.sharedInstance().setReminder(forMessage: message, withTimestamp: timestamp) { error in
            XCTAssertNil(error)

            NCAPIController.sharedInstance().getReminder(forMessage: message) { responseDict, error in
                XCTAssertNil(error)
                XCTAssertEqual(responseDict!["timestamp"] as? Int, timestamp)

                NCAPIController.sharedInstance().deleteReminder(forMessage: message) { error in
                    XCTAssertNil(error)

                    NCAPIController.sharedInstance().getReminder(forMessage: message) { responseDict, error in
                        XCTAssertNotNil(error)
                        XCTAssertEqual(error?.responseStatusCode, 404)
                        XCTAssertNil(responseDict)

                        exp.fulfill()
                    }
                }
            }
        }

        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)
    }

    func testDeleteMessage() async throws {
        try skipWithoutCapability(capability: kCapabilityDeleteMessages)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let chatMessage = "Deltable Message"

        let room = try await createUniqueRoom(prefix: "Delete message room", withAccount: activeAccount)
        let (message, _) = try await sendMessage(message: chatMessage, inRoom: room.token, withAccount: activeAccount)

        let exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().deleteChatMessage(inRoom: room.token, withMessageId: message.messageId, forAccount: activeAccount) { message, error, statusCode in
            XCTAssertEqual(NCChatMessage(dictionary: message)!.systemMessage, "message_deleted")
            XCTAssertNil(error)
            XCTAssertEqual(statusCode, 200)
            exp.fulfill()
        }

        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)
    }

}
