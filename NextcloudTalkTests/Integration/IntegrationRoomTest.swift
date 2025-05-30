//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
import Foundation
@testable import NextcloudTalk

final class IntegrationRoomTest: TestBase {

    func testRoomList() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        let exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().getRooms(forAccount: activeAccount, updateStatus: false, modifiedSince: 0) { rooms, error in
            XCTAssertNil(error)

            // By default, the room list should never be empty, it should contain atleast the talk changelog room
            XCTAssertGreaterThan(rooms?.count ?? 0, 0)

            exp.fulfill()
        }

        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)
    }

    func testRoomCreationAndDeletion() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomName = "Integration Test Room " + UUID().uuidString

        let exp = expectation(description: "\(#function)\(#line)")

        // Create a room
        NCAPIController.sharedInstance().createRoom(forAccount: activeAccount, withInvite: nil, ofType: .public, andName: roomName) { _, error in
            XCTAssertNil(error)

            self.checkRoomExists(roomName: roomName, withAccount: activeAccount) { room in

                // Delete the room again
                NCAPIController.sharedInstance().deleteRoom(room!.token, forAccount: activeAccount) { error in
                    XCTAssertNil(error)

                    self.checkRoomNotExists(roomName: roomName, withAccount: activeAccount) {
                        exp.fulfill()
                    }
                }
            }
        }

        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)
    }

    func testRoomDescription() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomName = "Description Test Room " + UUID().uuidString
        let roomDescription = "This is a room description"

        let exp = expectation(description: "\(#function)\(#line)")

        var roomToken = ""

        // Create a room
        NCAPIController.sharedInstance().createRoom(forAccount: activeAccount, withInvite: nil, ofType: .public, andName: roomName) { room, error in
            XCTAssertNil(error)

            roomToken = room?.token ?? ""

            exp.fulfill()
        }

        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)

        let expDescription = expectation(description: "\(#function)\(#line)")

        // Set a description
        NCAPIController.sharedInstance().setRoomDescription(roomDescription, forRoom: roomToken, forAccount: activeAccount) { error in
            XCTAssertNil(error)

            self.checkRoomExists(roomName: roomName, withAccount: activeAccount) { room in
                XCTAssertEqual(room?.roomDescription, roomDescription)
                expDescription.fulfill()
            }
        }

        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)
    }

    func testRoomRename() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomName = "Rename Test Room " + UUID().uuidString
        let roomNameNew = "\(roomName)- New"

        let exp = expectation(description: "\(#function)\(#line)")

        var roomToken = ""

        // Create a room
        NCAPIController.sharedInstance().createRoom(forAccount: activeAccount, withInvite: nil, ofType: .public, andName: roomName) { room, error in
            XCTAssertNil(error)

            roomToken = room?.token ?? ""

            exp.fulfill()
        }

        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)

        let expNewName = expectation(description: "\(#function)\(#line)")

        // Set a new name
        NCAPIController.sharedInstance().renameRoom(roomToken, forAccount: activeAccount, withName: roomNameNew) { error in
            XCTAssertNil(error)

            self.checkRoomExists(roomName: roomNameNew, withAccount: activeAccount) { room in
                XCTAssertEqual(room?.displayName, roomNameNew)
                expNewName.fulfill()
            }
        }

        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)
    }

    func testRoomPublicPrivate() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomName = "PublicPrivate Test Room " + UUID().uuidString

        var exp = expectation(description: "\(#function)\(#line)")
        var roomToken = ""

        // Create a room
        NCAPIController.sharedInstance().createRoom(forAccount: activeAccount, withInvite: nil, ofType: .group, andName: roomName) { room, error in
            XCTAssertNil(error)

            roomToken = room?.token ?? ""
            XCTAssert(room?.type == .group)

            exp.fulfill()
        }

        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)

        // Make room public
        exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().makeRoomPublic(roomToken, forAccount: activeAccount) { error in
            XCTAssertNil(error)

            NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: roomToken) { roomDict, error in
                XCTAssertNil(error)

                let room = NCRoom(dictionary: roomDict, andAccountId: activeAccount.accountId)
                XCTAssertNotNil(room)
                XCTAssert(room?.type == .public)

                exp.fulfill()
            }
        }

        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)

        // Make room private again
        exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().makeRoomPrivate(roomToken, forAccount: activeAccount) { error in
            XCTAssertNil(error)

            NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: roomToken) { roomDict, error in
                XCTAssertNil(error)

                let room = NCRoom(dictionary: roomDict, andAccountId: activeAccount.accountId)
                XCTAssertNotNil(room)
                XCTAssert(room?.type == .group)

                exp.fulfill()
            }
        }

        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)
    }

    func testRoomPassword() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomName = "Password Test Room " + UUID().uuidString

        var exp = expectation(description: "\(#function)\(#line)")
        var roomToken = ""

        // Create a room
        NCAPIController.sharedInstance().createRoom(forAccount: activeAccount, withInvite: nil, ofType: .public, andName: roomName) { room, error in
            XCTAssertNil(error)

            roomToken = room?.token ?? ""

            exp.fulfill()
        }

        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)

        // Set a password
        exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().setPassword("1234", forRoom: roomToken, forAccount: activeAccount) { error, _  in
            XCTAssertNil(error)

            self.checkRoomExists(roomName: roomName, withAccount: activeAccount) { room in
                XCTAssertTrue(room?.hasPassword ?? false)

                // Remove password again
                NCAPIController.sharedInstance().setPassword("", forRoom: roomToken, forAccount: activeAccount) { error, _ in
                    XCTAssertNil(error)

                    self.checkRoomExists(roomName: roomName, withAccount: activeAccount) { room in
                        XCTAssertFalse(room?.hasPassword ?? true)

                        exp.fulfill()
                    }
                }
            }
        }

        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)
    }

    func testRoomFavorite() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomName = "Favorite Test Room " + UUID().uuidString

        var exp = expectation(description: "\(#function)\(#line)")
        var roomToken = ""

        // Create a room
        NCAPIController.sharedInstance().createRoom(forAccount: activeAccount, withInvite: nil, ofType: .public, andName: roomName) { room, error in
            XCTAssertNil(error)

            roomToken = room?.token ?? ""

            exp.fulfill()
        }

        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)

        // Set as favorite
        exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().addRoomToFavorites(roomToken, forAccount: activeAccount) { error  in
            XCTAssertNil(error)

            self.checkRoomExists(roomName: roomName, withAccount: activeAccount) { room in
                XCTAssertTrue(room?.isFavorite ?? false)

                // Remove from favorite
                NCAPIController.sharedInstance().removeRoomFromFavorites(roomToken, forAccount: activeAccount) { error in
                    XCTAssertNil(error)

                    self.checkRoomExists(roomName: roomName, withAccount: activeAccount) { room in
                        XCTAssertFalse(room?.isFavorite ?? true)

                        exp.fulfill()
                    }
                }
            }
        }

        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)
    }

    func testRoomImportantConversation() async throws {
        try skipWithoutCapability(capability: kCapabilityImportantConversations)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = try await createUniqueRoom(prefix: "ImportantConversation", withAccount: activeAccount)

        // Set to important
        var updatedRoom = try await NCAPIController.sharedInstance().setImportantState(enabled: true, forRoom: room.token, forAccount: activeAccount)
        XCTAssertTrue(try XCTUnwrap(updatedRoom).isImportant)

        // Set to unimportant again
        updatedRoom = try await NCAPIController.sharedInstance().setImportantState(enabled: false, forRoom: room.token, forAccount: activeAccount)
        XCTAssertFalse(try XCTUnwrap(updatedRoom).isImportant)
    }

    func testRoomSensitiveConversation() async throws {
        try skipWithoutCapability(capability: kCapabilitySensitiveConversations)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = try await createUniqueRoom(prefix: "SensitiveConversation", withAccount: activeAccount)

        // TODO: Check for lastMessage does not work, since we don't create a reference to the lastMessage when creating a room just by a dict
        /*
        let message = "SensitiveTestMessage"

        // Send a message
        let exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().sendChatMessage(message, toRoom: room.token, displayName: "", replyTo: 0, referenceId: "", silently: false, for: activeAccount) { error in
            XCTAssertNil(error)

            let chatController = NCChatController(for: room)!
            chatController.updateHistoryInBackground { _ in
                exp.fulfill()
            }
        }

        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)
         */

        // Set to sensitive
        var updatedRoom = try await NCAPIController.sharedInstance().setSensitiveState(enabled: true, forRoom: room.token, forAccount: activeAccount)
        XCTAssertTrue(try XCTUnwrap(updatedRoom).isSensitive)

        // Set to non-sensitive again
        updatedRoom = try await NCAPIController.sharedInstance().setSensitiveState(enabled: false, forRoom: room.token, forAccount: activeAccount)
        XCTAssertFalse(try XCTUnwrap(updatedRoom).isSensitive)
    }

    func testRoomNotificationSettings() async throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = try await createUniqueRoom(prefix: "NotificationConversation", withAccount: activeAccount)

        // Test chat notification levels
        _ = await NCAPIController.sharedInstance().setNotificationLevel(level: .always, forRoom: room.token, forAccount: activeAccount)
        var updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        XCTAssertEqual(try XCTUnwrap(updatedRoom).notificationLevel, NCRoomNotificationLevel.always)

        _ = await NCAPIController.sharedInstance().setNotificationLevel(level: .mention, forRoom: room.token, forAccount: activeAccount)
        updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        XCTAssertEqual(try XCTUnwrap(updatedRoom).notificationLevel, NCRoomNotificationLevel.mention)

        _ = await NCAPIController.sharedInstance().setNotificationLevel(level: .never, forRoom: room.token, forAccount: activeAccount)
        updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        XCTAssertEqual(try XCTUnwrap(updatedRoom).notificationLevel, NCRoomNotificationLevel.never)

        // Test call notification setting
        _ = await NCAPIController.sharedInstance().setCallNotificationLevel(enabled: false, forRoom: room.token, forAccount: activeAccount)
        updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        XCTAssertEqual(try XCTUnwrap(updatedRoom).notificationCalls, false)

        _ = await NCAPIController.sharedInstance().setCallNotificationLevel(enabled: true, forRoom: room.token, forAccount: activeAccount)
        updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        XCTAssertEqual(try XCTUnwrap(updatedRoom).notificationCalls, true)
    }

    func testRoomSettings() async throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = try await createUniqueRoom(prefix: "SettingConversation", withAccount: activeAccount)

        // Read only state
        try await NCAPIController.sharedInstance().setReadOnlyState(state: .readOnly, forRoom: room.token, forAccount: activeAccount)
        var updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        XCTAssertEqual(try XCTUnwrap(updatedRoom).readOnlyState, .readOnly)

        try await NCAPIController.sharedInstance().setReadOnlyState(state: .readWrite, forRoom: room.token, forAccount: activeAccount)
        updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        XCTAssertEqual(try XCTUnwrap(updatedRoom).readOnlyState, .readWrite)

        // Lobby state
        try await NCAPIController.sharedInstance().setLobbyState(state: .moderatorsOnly, withTimer: 0, forRoom: room.token, forAccount: activeAccount)
        updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        XCTAssertEqual(try XCTUnwrap(updatedRoom).lobbyState, .moderatorsOnly)
        XCTAssertEqual(try XCTUnwrap(updatedRoom).lobbyTimer, 0)

        let timestamp = Int(Date().timeIntervalSince1970 + 3600)
        try await NCAPIController.sharedInstance().setLobbyState(state: .moderatorsOnly, withTimer: timestamp, forRoom: room.token, forAccount: activeAccount)
        updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        XCTAssertEqual(try XCTUnwrap(updatedRoom).lobbyState, .moderatorsOnly)
        XCTAssertEqual(try XCTUnwrap(updatedRoom).lobbyTimer, timestamp)

        try await NCAPIController.sharedInstance().setLobbyState(state: .allParticipants, withTimer: 0, forRoom: room.token, forAccount: activeAccount)
        updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        XCTAssertEqual(try XCTUnwrap(updatedRoom).lobbyState, .allParticipants)
        XCTAssertEqual(try XCTUnwrap(updatedRoom).lobbyTimer, 0)
    }

    func testRoomListable() async throws {
        try skipWithoutCapability(capability: kCapabilityListableRooms)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = try await createUniqueRoom(prefix: "ListableConversation", withAccount: activeAccount)

        try await NCAPIController.sharedInstance().setListableScope(scope: .regularUsersOnly, forRoom: room.token, forAccount: activeAccount)
        var updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        XCTAssertEqual(try XCTUnwrap(updatedRoom).listable, .regularUsersOnly)

        try await NCAPIController.sharedInstance().setListableScope(scope: .participantsOnly, forRoom: room.token, forAccount: activeAccount)
        updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        XCTAssertEqual(try XCTUnwrap(updatedRoom).listable, .participantsOnly)
    }

    func testRoomMessageExpiration() async throws {
        try skipWithoutCapability(capability: kCapabilityMessageExpiration)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = try await createUniqueRoom(prefix: "ExpirationConversation", withAccount: activeAccount)

        try await NCAPIController.sharedInstance().setMessageExpiration(messageExpiration: .expiration1Day, forRoom: room.token, forAccount: activeAccount)
        var updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        XCTAssertEqual(try XCTUnwrap(updatedRoom).messageExpiration, .expiration1Day)

        try await NCAPIController.sharedInstance().setMessageExpiration(messageExpiration: .expirationOff, forRoom: room.token, forAccount: activeAccount)
        updatedRoom = try await NCAPIController.sharedInstance().getRoom(forAccount: activeAccount, withToken: room.token)
        XCTAssertEqual(try XCTUnwrap(updatedRoom).messageExpiration, .expirationOff)
    }

    func testRoomParticipants() async throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = try await createUniqueRoom(prefix: "ParticipantConversation", withAccount: activeAccount)

        try await NCAPIController.sharedInstance().addParticipant("alice", ofType: "users", toRoom: room.token, forAccount: activeAccount)
        let participants = try await NCAPIController.sharedInstance().getParticipants(forRoom: room.token, forAccount: activeAccount)

        XCTAssertTrue(participants.contains { $0.displayName == "alice" })

        do {
            try await NCAPIController.sharedInstance().removeSelf(fromRoom: room.token, forAccount: activeAccount)
            XCTFail("OcsError expected")
        } catch {
            let error = try XCTUnwrap(error as? OcsError)
            XCTAssertEqual(error.responseStatusCode, 400)
        }
    }
}
