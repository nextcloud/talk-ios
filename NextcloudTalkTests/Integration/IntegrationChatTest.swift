//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Testing
@testable import NextcloudTalk

@Suite(.serialized)
final class IntegrationChatTest: TestBase {

    @Test func `send message`() async throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let chatMessage = "Test Message 😀😆"

        let room = try await createUniqueRoom(prefix: "Integration Test Room 👍", withAccount: activeAccount)
        let (message, details) = try await sendMessage(message: chatMessage, inRoom: room.token, withAccount: activeAccount)

        #expect(message.message == chatMessage)
        #expect(message.token == room.token)
        #expect(details.statusCode == 200)
        #expect(details.lastKnownMessage > 0)

        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().receiveChatMessages(ofRoom: room.token, fromLastMessageId: details.lastKnownMessage, inThread: 0, history: false, includeLastMessage: false, timeout: false, limit: 0, lastCommonReadMessage: 0, setReadMarker: false, markNotificationsAsRead: false, forAccount: activeAccount, completionBlock: { messages, lastKnownMessage, _, error, statusCode in
                #expect(messages == nil)
                #expect(lastKnownMessage == -1)
                #expect(statusCode == 304)
                #expect(error != nil)

                continuation.resume()
            })
        }
    }

    @Test func `pin message`() async throws {
        try skipWithoutCapability(capability: kCapabilityPinnedMessages)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let chatMessage = "Test Message 😀😆"

        let room = try await createUniqueRoom(prefix: "Pin message room", withAccount: activeAccount)
        let (message, _) = try await sendMessage(message: chatMessage, inRoom: room.token, withAccount: activeAccount)

        // Pin message
        _ = try await NCAPIController.sharedInstance().pinMessage(message.messageId, inRoom: room.token, pinUntil: 0, forAccount: activeAccount)
        var updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        #expect(try #require(updatedRoom).lastPinnedId == message.messageId)

        _ = try await NCAPIController.sharedInstance().unpinMessageForSelf(message.messageId, inRoom: room.token, forAccount: activeAccount)
        updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        #expect(try #require(updatedRoom).lastPinnedId == message.messageId)
        #expect(try #require(updatedRoom).hiddenPinnedId == message.messageId)

        _ = try await NCAPIController.sharedInstance().unpinMessage(message.messageId, inRoom: room.token, forAccount: activeAccount)
        updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        #expect(try #require(updatedRoom).lastPinnedId == 0)
    }

    @Test func `schedule messages`() async throws {
        try skipWithoutCapability(capability: kCapabilityScheduleMessages)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let chatMessage = "Scheduled Message 😀😆"
        let chatMessageEdited = "Scheduled Message 😀😆 Edited"

        let room = try await createUniqueRoom(prefix: "Schedule message room", withAccount: activeAccount)

        // Ensure no message was scheduled in the room
        var scheduledMessages = try await NCAPIController.sharedInstance().getScheduledMessages(forRoom: room.token, forAccount: activeAccount)
        #expect(scheduledMessages.isEmpty)

        // Schedule our first message
        let timestamp = Int(Date().timeIntervalSince1970 + 300)
        var message = try await NCAPIController.sharedInstance().scheduleMessage(chatMessage, inRoom: room.token, sendAt: timestamp, forAccount: activeAccount)
        #expect(message != nil)

        // Check if we can retrieve the scheduled message
        scheduledMessages = try await NCAPIController.sharedInstance().getScheduledMessages(forRoom: room.token, forAccount: activeAccount)
        #expect(scheduledMessages.count == 1)
        let firstMessage = scheduledMessages.first!
        #expect(firstMessage.message == chatMessage)
        #expect(firstMessage.sendAtTimestamp == timestamp)
        #expect(firstMessage.id == message?.id)

        // Edit the scheduled message
        #expect(firstMessage.id != nil)
        message = try await NCAPIController.sharedInstance().editScheduledMessage(firstMessage.id, withMessage: chatMessageEdited, inRoom: room.token, sendAt: timestamp, forAccount: activeAccount)

        // Check if we can retrieve the edited scheduled message
        scheduledMessages = try await NCAPIController.sharedInstance().getScheduledMessages(forRoom: room.token, forAccount: activeAccount)
        #expect(scheduledMessages.count == 1)
        #expect(scheduledMessages.first?.message == chatMessageEdited)
        #expect(scheduledMessages.first?.id == message?.id)

        // Delete the scheduled message
        try await NCAPIController.sharedInstance().deleteScheduledMessage(firstMessage.id, inRoom: room.token, forAccount: activeAccount)

        // No scheduled messages should be there anymore
        scheduledMessages = try await NCAPIController.sharedInstance().getScheduledMessages(forRoom: room.token, forAccount: activeAccount)
        #expect(scheduledMessages.isEmpty)
    }

    @Test func `message reaction`() async throws {
        try skipWithoutCapability(capability: kCapabilityReactions)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let chatMessage = "React to message 🥳"

        let room = try await createUniqueRoom(prefix: "Reaction Test Room 🧊", withAccount: activeAccount)
        let (message, _) = try await sendMessage(message: chatMessage, inRoom: room.token, withAccount: activeAccount)

        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().addReaction("👍", toMessage: message.messageId, inRoom: room.token, forAccount: activeAccount) { reactionsDict, error in
                #expect(error == nil)
                #expect(reactionsDict!["👍"] != nil)

                NCAPIController.sharedInstance().getReactions(nil, fromMessage: message.messageId, inRoom: room.token, forAccount: activeAccount) { reactionsDict, error in
                    #expect(error == nil)
                    #expect(reactionsDict!["👍"] != nil)

                    NCAPIController.sharedInstance().removeReaction("👍", fromMessage: message.messageId, inRoom: room.token, forAccount: activeAccount) { reactionsDict, error in
                        #expect(error == nil)
                        #expect(reactionsDict!["👍"] == nil)

                        NCAPIController.sharedInstance().getReactions(nil, fromMessage: message.messageId, inRoom: room.token, forAccount: activeAccount) { reactionsDict, error in
                            #expect(error == nil)
                            #expect(reactionsDict!["👍"] == nil)

                            continuation.resume()
                        }
                    }
                }
            }
        }
    }

    @Test func `message reminder`() async throws {
        try skipWithoutCapability(capability: kCapabilityRemindMeLater)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let chatMessage = "Reminded message"

        let room = try await createUniqueRoom(prefix: "Reminder Test Room", withAccount: activeAccount)
        let (message, _) = try await sendMessage(message: chatMessage, inRoom: room.token, withAccount: activeAccount)

        let timestamp = Int(Date().timeIntervalSince1970)

        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().setReminder(forMessage: message, withTimestamp: timestamp) { error in
                #expect(error == nil)

                NCAPIController.sharedInstance().getReminder(forMessage: message) { responseDict, error in
                    #expect(error == nil)
                    #expect(responseDict!["timestamp"] as? Int == timestamp)

                    NCAPIController.sharedInstance().deleteReminder(forMessage: message) { error in
                        #expect(error == nil)

                        NCAPIController.sharedInstance().getReminder(forMessage: message) { responseDict, error in
                            #expect(error != nil)
                            #expect(error?.responseStatusCode == 404)
                            #expect(responseDict == nil)

                            continuation.resume()
                        }
                    }
                }
            }
        }
    }

    @Test func `delete message`() async throws {
        try skipWithoutCapability(capability: kCapabilityDeleteMessages)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let chatMessage = "Deltable Message"

        let room = try await createUniqueRoom(prefix: "Delete message room", withAccount: activeAccount)
        let (message, _) = try await sendMessage(message: chatMessage, inRoom: room.token, withAccount: activeAccount)

        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().deleteChatMessage(inRoom: room.token, withMessageId: message.messageId, forAccount: activeAccount) { deleteMessage, error, statusCode in
                // Since we don't store messages, we can't access chatMessage.parent here directly (it's always retrieved through internalId)
                let chatMessage = NCChatMessage(dictionary: deleteMessage)!
                let parentMessage = NCChatMessage(dictionary: deleteMessage!["parent"] as! [String: Any])!

                #expect(chatMessage.systemMessage == "message_deleted")
                #expect(error == nil)
                #expect(statusCode == 200)
                #expect(parentMessage.messageId == message.messageId)

                continuation.resume()
            }
        }
    }

    @Test func `edit message`() async throws {
        try skipWithoutCapability(capability: kCapabilityEditMessages)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let chatMessage = "Editable Message"
        let newChatMessage = "Edited message"

        let room = try await createUniqueRoom(prefix: "Edit message room", withAccount: activeAccount)
        let (message, _) = try await sendMessage(message: chatMessage, inRoom: room.token, withAccount: activeAccount)

        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().editChatMessage(inRoom: room.token, withMessageId: message.messageId, withMessage: newChatMessage, forAccount: activeAccount) { editedMessage, error, statusCode in
                // Since we don't store messages, we can't access chatMessage.parent here directly (it's always retrieved through internalId)
                let chatMessage = NCChatMessage(dictionary: editedMessage)!
                let parentMessage = NCChatMessage(dictionary: editedMessage!["parent"] as! [String: Any])!

                #expect(chatMessage.systemMessage == "message_edited")
                #expect(error == nil)
                #expect(statusCode == 200)
                #expect(parentMessage.messageId == message.messageId)
                #expect(parentMessage.message == newChatMessage)

                continuation.resume()
            }
        }
    }

    @Test func `clear history`() async throws {
        try skipWithoutCapability(capability: kCapabilityClearHistory)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let chatMessage = "Before clear history Message"

        let room = try await createUniqueRoom(prefix: "Clear history room", withAccount: activeAccount)
        try await sendMessage(message: chatMessage, inRoom: room.token, withAccount: activeAccount)

        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().clearChatHistory(inRoom: room.token, forAccount: activeAccount) { message, error in
                let chatMessage = NCChatMessage(dictionary: message)!

                #expect(chatMessage.systemMessage == "history_cleared")
                #expect(error == nil)

                continuation.resume()
            }
        }
    }

    @Test func `share rich object`() async throws {
        try skipWithoutCapability(capability: kCapabilityLocationSharing)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        let room = try await createUniqueRoom(prefix: "Rich object room", withAccount: activeAccount)
        let richObject = GeoLocationRichObject(latitude: 48.858093, longitude: 2.294694, name: "Tour Eiffel")

        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().shareRichObject(richObject.richObjectDictionary(), inRoom: room.token, forAccount: activeAccount) { error in
                #expect(error == nil)
                continuation.resume()
            }
        }
    }

    @Test func `read marker`() async throws {
        try skipWithoutCapability(capability: kCapabilityChatReadLast)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        let room = try await createUniqueRoom(prefix: "Read marker room", withAccount: activeAccount)
        let (message1, _) = try await sendMessage(message: "Message1", inRoom: room.token, withAccount: activeAccount)
        let (message2, _) = try await sendMessage(message: "Message2", inRoom: room.token, withAccount: activeAccount)
        try await sendMessage(message: "Message3", inRoom: room.token, withAccount: activeAccount)

        await withCheckedContinuation { continuation in
            // Set read marker to a specific messageId
            NCAPIController.sharedInstance().setChatReadMarker(message1.messageId, inRoom: room.token, forAccount: activeAccount) { error in
                #expect(error == nil)

                // Check if the set ID is correctly reflected in rooms list
                NCAPIController.sharedInstance().getRooms(forAccount: activeAccount, updateStatus: false, modifiedSince: 0) { roomsDict, error in
                    #expect(error == nil)

                    let rooms = self.getRoomDict(from: roomsDict!, for: activeAccount)
                    let foundRoom = rooms.first(where: { $0.token == room.token })

                    #expect(foundRoom?.lastReadMessage == message1.messageId)

                    // markChatAsUnread sets the lastReadMessage to the last-1 message, message2 in our test case
                    NCAPIController.sharedInstance().markChatAsUnread(inRoom: room.token, forAccount: activeAccount) { error in
                        #expect(error == nil)

                        // Check again if that is correctly reflected in the rooms list
                        NCAPIController.sharedInstance().getRooms(forAccount: activeAccount, updateStatus: false, modifiedSince: 0) { roomsDict, error in
                            #expect(error == nil)

                            let rooms = self.getRoomDict(from: roomsDict!, for: activeAccount)
                            let foundRoom = rooms.first(where: { $0.token == room.token })

                            #expect(foundRoom?.lastReadMessage == message2.messageId)

                            continuation.resume()
                        }
                    }
                }
            }
        }
    }

    @Test func `share overview`() async throws {
        try skipWithoutCapability(capability: kCapabilityRichObjectListMedia)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        let room = try await createUniqueRoom(prefix: "Rich object room", withAccount: activeAccount)
        let richObject = GeoLocationRichObject(latitude: 48.858093, longitude: 2.294694, name: "Tour Eiffel")

        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().shareRichObject(richObject.richObjectDictionary(), inRoom: room.token, forAccount: activeAccount) { error in
                #expect(error == nil)
                continuation.resume()
            }
        }

        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().getSharedItemsOverview(inRoom: room.token, withLimit: -1, forAccount: activeAccount) { sharedItemsOverview, error in
                #expect(error == nil)
                #expect(sharedItemsOverview?["location"]?.first != nil)
                continuation.resume()
            }
        }

        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().getSharedItems(ofType: "location", fromLastMessageId: 0, inRoom: room.token, withLimit: -1, forAccount: activeAccount) { sharedItems, lastKnownMessageId, error in
                #expect(error == nil)
                #expect(sharedItems?.count == 1)
                #expect(lastKnownMessageId > 0)
                continuation.resume()
            }
        }
    }

}
