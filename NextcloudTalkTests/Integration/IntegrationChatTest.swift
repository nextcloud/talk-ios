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
        NCAPIController.sharedInstance().deleteChatMessage(inRoom: room.token, withMessageId: message.messageId, forAccount: activeAccount) { deleteMessage, error, statusCode in
            // Since we don't store messages, we can't access chatMessage.parent here directly (it's always retrieved through internalId)
            let chatMessage = NCChatMessage(dictionary: deleteMessage)!
            let parentMessage = NCChatMessage(dictionary: deleteMessage!["parent"] as! [String: Any])!

            XCTAssertEqual(chatMessage.systemMessage, "message_deleted")
            XCTAssertNil(error)
            XCTAssertEqual(statusCode, 200)
            XCTAssertEqual(parentMessage.messageId, message.messageId)

            exp.fulfill()
        }

        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)
    }

    func testEditMessage() async throws {
        try skipWithoutCapability(capability: kCapabilityEditMessages)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let chatMessage = "Editable Message"
        let newChatMessage = "Edited message"

        let room = try await createUniqueRoom(prefix: "Edit message room", withAccount: activeAccount)
        let (message, _) = try await sendMessage(message: chatMessage, inRoom: room.token, withAccount: activeAccount)

        let exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().editChatMessage(inRoom: room.token, withMessageId: message.messageId, withMessage: newChatMessage, forAccount: activeAccount) { editedMessage, error, statusCode in
            // Since we don't store messages, we can't access chatMessage.parent here directly (it's always retrieved through internalId)
            let chatMessage = NCChatMessage(dictionary: editedMessage)!
            let parentMessage = NCChatMessage(dictionary: editedMessage!["parent"] as! [String: Any])!

            XCTAssertEqual(chatMessage.systemMessage, "message_edited")
            XCTAssertNil(error)
            XCTAssertEqual(statusCode, 200)
            XCTAssertEqual(parentMessage.messageId, message.messageId)
            XCTAssertEqual(parentMessage.message, newChatMessage)

            exp.fulfill()
        }

        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)
    }

    func testClearHistory() async throws {
        try skipWithoutCapability(capability: kCapabilityClearHistory)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let chatMessage = "Before clear history Message"

        let room = try await createUniqueRoom(prefix: "Clear history room", withAccount: activeAccount)
        try await sendMessage(message: chatMessage, inRoom: room.token, withAccount: activeAccount)

        let exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().clearChatHistory(inRoom: room.token, forAccount: activeAccount) { message, error in
            let chatMessage = NCChatMessage(dictionary: message)!

            XCTAssertEqual(chatMessage.systemMessage, "history_cleared")
            XCTAssertNil(error)

            exp.fulfill()
        }

        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)
    }

    func testShareRichObject() async throws {
        try skipWithoutCapability(capability: kCapabilityLocationSharing)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        let room = try await createUniqueRoom(prefix: "Rich object room", withAccount: activeAccount)
        let richObject = GeoLocationRichObject(latitude: 48.858093, longitude: 2.294694, name: "Tour Eiffel")

        let exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().shareRichObject(richObject.richObjectDictionary(), inRoom: room.token, forAccount: activeAccount) { error in
            XCTAssertNil(error)
            exp.fulfill()
        }

        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)
    }

    func testReadMarker() async throws {
        try skipWithoutCapability(capability: kCapabilityChatReadLast)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        let room = try await createUniqueRoom(prefix: "Read marker room", withAccount: activeAccount)
        let (message1, _) = try await sendMessage(message: "Message1", inRoom: room.token, withAccount: activeAccount)
        let (message2, _) = try await sendMessage(message: "Message2", inRoom: room.token, withAccount: activeAccount)
        try await sendMessage(message: "Message3", inRoom: room.token, withAccount: activeAccount)

        let exp = expectation(description: "\(#function)\(#line)")
        // Set read marker to a specific messageId
        NCAPIController.sharedInstance().setChatReadMarker(message1.messageId, inRoom: room.token, forAccount: activeAccount) { error in
            XCTAssertNil(error)

            // Check if the set ID is correctly reflected in rooms list
            NCAPIController.sharedInstance().getRooms(forAccount: activeAccount, updateStatus: false, modifiedSince: 0) { roomsDict, error in
                XCTAssertNil(error)

                let rooms = self.getRoomDict(from: roomsDict!, for: activeAccount)
                let foundRoom = rooms.first(where: { $0.token == room.token })

                XCTAssertEqual(foundRoom?.lastReadMessage, message1.messageId)

                // markChatAsUnread sets the lastReadMessage to the last-1 message, message2 in our test case
                NCAPIController.sharedInstance().markChatAsUnread(inRoom: room.token, forAccount: activeAccount) { error in
                    XCTAssertNil(error)

                    // Check again if that is correctly reflected in the rooms list
                    NCAPIController.sharedInstance().getRooms(forAccount: activeAccount, updateStatus: false, modifiedSince: 0) { roomsDict, error in
                        XCTAssertNil(error)

                        let rooms = self.getRoomDict(from: roomsDict!, for: activeAccount)
                        let foundRoom = rooms.first(where: { $0.token == room.token })

                        XCTAssertEqual(foundRoom?.lastReadMessage, message2.messageId)

                        exp.fulfill()
                    }
                }
            }
        }

        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)
    }

    func testShareOverview() async throws {
        try skipWithoutCapability(capability: kCapabilityRichObjectListMedia)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        let room = try await createUniqueRoom(prefix: "Rich object room", withAccount: activeAccount)
        let richObject = GeoLocationRichObject(latitude: 48.858093, longitude: 2.294694, name: "Tour Eiffel")

        var exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().shareRichObject(richObject.richObjectDictionary(), inRoom: room.token, forAccount: activeAccount) { error in
            XCTAssertNil(error)
            exp.fulfill()
        }

        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)

        exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().getSharedItemsOverview(inRoom: room.token, withLimit: -1, forAccount: activeAccount) { sharedItemsOverview, error in
            XCTAssertNil(error)
            XCTAssertNotNil(sharedItemsOverview?["location"]?.first)
            exp.fulfill()
        }

        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)

        exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().getSharedItems(ofType: "location", fromLastMessageId: 0, inRoom: room.token, withLimit: -1, forAccount: activeAccount) { sharedItems, lastKnownMessageId, error in
            XCTAssertNil(error)
            XCTAssertEqual(sharedItems?.count, 1)
            XCTAssertGreaterThan(lastKnownMessageId, 0)
            exp.fulfill()
        }

        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)
    }

}
