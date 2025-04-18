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
}
