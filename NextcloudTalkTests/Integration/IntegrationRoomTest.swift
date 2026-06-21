//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Testing
@testable import NextcloudTalk

@Suite(.serialized)
final class IntegrationRoomTest: TestBase {

    @Test func `room list`() async {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().getRooms(forAccount: activeAccount, updateStatus: false, modifiedSince: 0) { rooms, error in
                #expect(error == nil)

                // By default, the room list should never be empty, it should contain atleast the talk changelog room
                #expect((rooms?.count ?? 0) > 0)

                continuation.resume()
            }
        }
    }

    @Test func `room creation and deletion`() async {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomName = "Integration Test Room " + UUID().uuidString

        await withCheckedContinuation { continuation in
            // Create a room
            NCAPIController.sharedInstance().createRoom(forAccount: activeAccount, withInvite: nil, ofType: .public, andName: roomName) { _, error in
                #expect(error == nil)

                self.checkRoomExists(roomName: roomName, withAccount: activeAccount) { room in

                    // Delete the room again
                    NCAPIController.sharedInstance().deleteRoom(room!.token, forAccount: activeAccount) { error in
                        #expect(error == nil)

                        self.checkRoomNotExists(roomName: roomName, withAccount: activeAccount) {
                            continuation.resume()
                        }
                    }
                }
            }
        }
    }

    @Test func `non existant one to one creation`() async {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().createRoom(forAccount: activeAccount, withInvite: "non-existant-userid", ofType: .oneToOne, andName: nil) { room, error in
                #expect(room == nil)
                #expect(error?.responseStatusCode == 404)

                // Not supported on older versions
                if NCDatabaseManager.sharedInstance().serverCapabilities()!.versionMajor >= 31 {
                    #expect(error?.errorKey == "invite")
                }

                continuation.resume()
            }
        }
    }

    @Test func `room description`() async {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomName = "Description Test Room " + UUID().uuidString
        let roomDescription = "This is a room description"

        // Create a room
        let roomToken: String = await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().createRoom(forAccount: activeAccount, withInvite: nil, ofType: .public, andName: roomName) { room, error in
                #expect(error == nil)
                continuation.resume(returning: room?.token ?? "")
            }
        }

        // Set a description
        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().setRoomDescription(roomDescription, forRoom: roomToken, forAccount: activeAccount) { error in
                #expect(error == nil)

                self.checkRoomExists(roomName: roomName, withAccount: activeAccount) { room in
                    #expect(room?.roomDescription == roomDescription)
                    continuation.resume()
                }
            }
        }
    }

    @Test func `room rename`() async {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomName = "Rename Test Room " + UUID().uuidString
        let roomNameNew = "\(roomName)- New"

        // Create a room
        let roomToken: String = await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().createRoom(forAccount: activeAccount, withInvite: nil, ofType: .public, andName: roomName) { room, error in
                #expect(error == nil)
                continuation.resume(returning: room?.token ?? "")
            }
        }

        // Set a new name
        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().renameRoom(roomToken, forAccount: activeAccount, withName: roomNameNew) { error in
                #expect(error == nil)

                self.checkRoomExists(roomName: roomNameNew, withAccount: activeAccount) { room in
                    #expect(room?.displayName == roomNameNew)
                    continuation.resume()
                }
            }
        }
    }

    @Test func `room public private`() async {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomName = "PublicPrivate Test Room " + UUID().uuidString

        // Create a room
        let roomToken: String = await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().createRoom(forAccount: activeAccount, withInvite: nil, ofType: .group, andName: roomName) { room, error in
                #expect(error == nil)
                #expect(room?.type == .group)
                continuation.resume(returning: room?.token ?? "")
            }
        }

        // Make room public
        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().makeRoomPublic(roomToken, forAccount: activeAccount) { error in
                #expect(error == nil)

                NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: roomToken) { roomDict, error in
                    #expect(error == nil)

                    let room = NCRoom(dictionary: roomDict, andAccountId: activeAccount.accountId)
                    #expect(room != nil)
                    #expect(room?.type == .public)

                    continuation.resume()
                }
            }
        }

        // Make room private again
        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().makeRoomPrivate(roomToken, forAccount: activeAccount) { error in
                #expect(error == nil)

                NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: roomToken) { roomDict, error in
                    #expect(error == nil)

                    let room = NCRoom(dictionary: roomDict, andAccountId: activeAccount.accountId)
                    #expect(room != nil)
                    #expect(room?.type == .group)

                    continuation.resume()
                }
            }
        }
    }

    @Test func `room password`() async {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomName = "Password Test Room " + UUID().uuidString

        // Create a room
        let roomToken: String = await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().createRoom(forAccount: activeAccount, withInvite: nil, ofType: .public, andName: roomName) { room, error in
                #expect(error == nil)
                continuation.resume(returning: room?.token ?? "")
            }
        }

        // Set a password
        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().setPassword("1234", forRoom: roomToken, forAccount: activeAccount) { error, _  in
                #expect(error == nil)

                self.checkRoomExists(roomName: roomName, withAccount: activeAccount) { room in
                    #expect(room?.hasPassword ?? false)

                    // Remove password again
                    NCAPIController.sharedInstance().setPassword("", forRoom: roomToken, forAccount: activeAccount) { error, _ in
                        #expect(error == nil)

                        self.checkRoomExists(roomName: roomName, withAccount: activeAccount) { room in
                            #expect(!(room?.hasPassword ?? true))

                            continuation.resume()
                        }
                    }
                }
            }
        }
    }

    @Test func `room favorite`() async {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomName = "Favorite Test Room " + UUID().uuidString

        // Create a room
        let roomToken: String = await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().createRoom(forAccount: activeAccount, withInvite: nil, ofType: .public, andName: roomName) { room, error in
                #expect(error == nil)
                continuation.resume(returning: room?.token ?? "")
            }
        }

        // Set as favorite
        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().addRoomToFavorites(roomToken, forAccount: activeAccount) { error  in
                #expect(error == nil)

                self.checkRoomExists(roomName: roomName, withAccount: activeAccount) { room in
                    #expect(room?.isFavorite ?? false)

                    // Remove from favorite
                    NCAPIController.sharedInstance().removeRoomFromFavorites(roomToken, forAccount: activeAccount) { error in
                        #expect(error == nil)

                        self.checkRoomExists(roomName: roomName, withAccount: activeAccount) { room in
                            #expect(!(room?.isFavorite ?? true))

                            continuation.resume()
                        }
                    }
                }
            }
        }
    }

    @Test func `room important conversation`() async throws {
        try skipWithoutCapability(capability: kCapabilityImportantConversations)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = try await createUniqueRoom(prefix: "ImportantConversation", withAccount: activeAccount)

        // Set to important
        var updatedRoom = try await NCAPIController.sharedInstance().setImportantState(enabled: true, forRoom: room.token, forAccount: activeAccount)
        #expect(try #require(updatedRoom).isImportant)

        // Set to unimportant again
        updatedRoom = try await NCAPIController.sharedInstance().setImportantState(enabled: false, forRoom: room.token, forAccount: activeAccount)
        #expect(!(try #require(updatedRoom).isImportant))
    }

    @Test func `room sensitive conversation`() async throws {
        try skipWithoutCapability(capability: kCapabilitySensitiveConversations)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = try await createUniqueRoom(prefix: "SensitiveConversation", withAccount: activeAccount)

        // TODO: Check for lastMessage does not work, since we don't create a reference to the lastMessage when creating a room just by a dict
        /*
        let message = "SensitiveTestMessage"

        // Send a message
        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().sendChatMessage(message, toRoom: room.token, displayName: "", replyTo: 0, referenceId: "", silently: false, for: activeAccount) { error in
                #expect(error == nil)

                let chatController = NCChatController(for: room)!
                chatController.updateHistoryInBackground { _ in
                    continuation.resume()
                }
            }
        }
         */

        // Set to sensitive
        var updatedRoom = try await NCAPIController.sharedInstance().setSensitiveState(enabled: true, forRoom: room.token, forAccount: activeAccount)
        #expect(try #require(updatedRoom).isSensitive)

        // Set to non-sensitive again
        updatedRoom = try await NCAPIController.sharedInstance().setSensitiveState(enabled: false, forRoom: room.token, forAccount: activeAccount)
        #expect(!(try #require(updatedRoom).isSensitive))
    }

    @Test func `room notification settings`() async throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = try await createUniqueRoom(prefix: "NotificationConversation", withAccount: activeAccount)

        // Test chat notification levels
        _ = await NCAPIController.sharedInstance().setNotificationLevel(level: .always, forRoom: room.token, forAccount: activeAccount)
        var updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        #expect(try #require(updatedRoom).notificationLevel == NCRoomNotificationLevel.always)

        _ = await NCAPIController.sharedInstance().setNotificationLevel(level: .mention, forRoom: room.token, forAccount: activeAccount)
        updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        #expect(try #require(updatedRoom).notificationLevel == NCRoomNotificationLevel.mention)

        _ = await NCAPIController.sharedInstance().setNotificationLevel(level: .never, forRoom: room.token, forAccount: activeAccount)
        updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        #expect(try #require(updatedRoom).notificationLevel == NCRoomNotificationLevel.never)

        // Test call notification setting
        _ = await NCAPIController.sharedInstance().setCallNotificationLevel(enabled: false, forRoom: room.token, forAccount: activeAccount)
        updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        #expect(try #require(updatedRoom).notificationCalls == false)

        _ = await NCAPIController.sharedInstance().setCallNotificationLevel(enabled: true, forRoom: room.token, forAccount: activeAccount)
        updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        #expect(try #require(updatedRoom).notificationCalls == true)
    }

    @Test func `room settings`() async throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = try await createUniqueRoom(prefix: "SettingConversation", withAccount: activeAccount)

        // Read only state
        try await NCAPIController.sharedInstance().setReadOnlyState(state: .readOnly, forRoom: room.token, forAccount: activeAccount)
        var updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        #expect(try #require(updatedRoom).readOnlyState == .readOnly)

        try await NCAPIController.sharedInstance().setReadOnlyState(state: .readWrite, forRoom: room.token, forAccount: activeAccount)
        updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        #expect(try #require(updatedRoom).readOnlyState == .readWrite)

        // Lobby state
        try await NCAPIController.sharedInstance().setLobbyState(state: .moderatorsOnly, withTimer: 0, forRoom: room.token, forAccount: activeAccount)
        updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        #expect(try #require(updatedRoom).lobbyState == .moderatorsOnly)
        #expect(try #require(updatedRoom).lobbyTimer == 0)

        let timestamp = Int(Date().timeIntervalSince1970 + 3600)
        try await NCAPIController.sharedInstance().setLobbyState(state: .moderatorsOnly, withTimer: timestamp, forRoom: room.token, forAccount: activeAccount)
        updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        #expect(try #require(updatedRoom).lobbyState == .moderatorsOnly)
        #expect(try #require(updatedRoom).lobbyTimer == timestamp)

        try await NCAPIController.sharedInstance().setLobbyState(state: .allParticipants, withTimer: 0, forRoom: room.token, forAccount: activeAccount)
        updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        #expect(try #require(updatedRoom).lobbyState == .allParticipants)
        #expect(try #require(updatedRoom).lobbyTimer == 0)
    }

    @Test func `room listable`() async throws {
        try skipWithoutCapability(capability: kCapabilityListableRooms)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = try await createUniqueRoom(prefix: "ListableConversation", withAccount: activeAccount)

        try await NCAPIController.sharedInstance().setListableScope(scope: .regularUsersOnly, forRoom: room.token, forAccount: activeAccount)
        var updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        #expect(try #require(updatedRoom).listable == .regularUsersOnly)

        try await NCAPIController.sharedInstance().setListableScope(scope: .participantsOnly, forRoom: room.token, forAccount: activeAccount)
        updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        #expect(try #require(updatedRoom).listable == .participantsOnly)
    }

    @Test func `room message expiration`() async throws {
        try skipWithoutCapability(capability: kCapabilityMessageExpiration)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = try await createUniqueRoom(prefix: "ExpirationConversation", withAccount: activeAccount)

        try await NCAPIController.sharedInstance().setMessageExpiration(messageExpiration: .expiration1Day, forRoom: room.token, forAccount: activeAccount)
        var updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        #expect(try #require(updatedRoom).messageExpiration == .expiration1Day)

        try await NCAPIController.sharedInstance().setMessageExpiration(messageExpiration: .expirationOff, forRoom: room.token, forAccount: activeAccount)
        updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        #expect(try #require(updatedRoom).messageExpiration == .expirationOff)
    }

    @Test func `room participants`() async throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = try await createUniqueRoom(prefix: "ParticipantConversation", withAccount: activeAccount)

        // Add alice as participant
        try await NCAPIController.sharedInstance().addParticipant("alice", ofType: "users", toRoom: room.token, forAccount: activeAccount)
        var participants = try await NCAPIController.sharedInstance().getParticipants(forRoom: room.token, forAccount: activeAccount)

        let participantAlice = try #require(participants.first(where: { $0.displayName == "alice" }))

        // Promote alice to moderator
        try await NCAPIController.sharedInstance().changeModerationPermission(forAttendeeId: participantAlice.attendeeId, withType: .promoteToModerator, inRoom: room.token, forAccount: activeAccount)
        participants = try await NCAPIController.sharedInstance().getParticipants(forRoom: room.token, forAccount: activeAccount)

        #expect(participants.contains { $0.displayName == "alice" && $0.canModerate })

        // Demote alice to participant
        try await NCAPIController.sharedInstance().changeModerationPermission(forAttendeeId: participantAlice.attendeeId, withType: .demoteToParticipant, inRoom: room.token, forAccount: activeAccount)
        participants = try await NCAPIController.sharedInstance().getParticipants(forRoom: room.token, forAccount: activeAccount)

        #expect(participants.contains { $0.displayName == "alice" && !$0.canModerate })

        // Also check that the test user is in the room and correctly identified as the app user
        #expect(participants.contains { $0.displayName == "admin" && $0.isAppUser })

        // Try to remove admin which should fail, as admin is the last moderator
        do {
            try await NCAPIController.sharedInstance().removeSelf(fromRoom: room.token, forAccount: activeAccount)
            Issue.record("OcsError expected")
        } catch {
            let error = try #require(error as? OcsError)
            #expect(error.responseStatusCode == 400)

            // Not supported on older versions
            if NCDatabaseManager.sharedInstance().serverCapabilities()!.versionMajor >= 31 {
                #expect(error.errorKey == "last-moderator")
            }
        }
    }

    @Test func `bot management`() async throws {
        try skipWithoutCapability(capability: kCapabilityBotV1)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = try await createUniqueRoom(prefix: "BotConversation", withAccount: activeAccount)

        let botList = try await NCAPIController.sharedInstance().getBots(forRoom: room.token, forAccount: activeAccount)
        #expect(botList.count == 1)

        let bot = try #require(botList.first)
        #expect(bot.name == "TestBot")
        #expect(bot.description == "New description")
        #expect(bot.state == .disabled)

        let enabledBot = try await NCAPIController.sharedInstance().enableBot(withId: bot.id, forRoom: room.token, forAccount: activeAccount)
        #expect(enabledBot?.name == "TestBot")
        #expect(enabledBot?.state == .enabled)

        let disabledBot = try await NCAPIController.sharedInstance().disableBot(withId: bot.id, forRoom: room.token, forAccount: activeAccount)
        #expect(disabledBot?.name == "TestBot")
        #expect(disabledBot?.state == .disabled)
    }

}
