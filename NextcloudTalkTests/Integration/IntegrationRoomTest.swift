//
// Copyright (c) 2023 Marcel Müller <marcel-mueller@gmx.de>
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

    func testRoomCreation() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomName = "Integration Test Room"

        let exp = expectation(description: "\(#function)\(#line)")

        // Create a room
        NCAPIController.sharedInstance().createRoom(forAccount: activeAccount, withInvite: nil, ofType: .public, andName: roomName) { _, error in
            XCTAssertNil(error)
            exp.fulfill()
        }

        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)

        self.checkRoomExists(roomName: roomName, withAccount: activeAccount)
    }

    func testRoomDescription() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomName = "Description Test Room"
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
            expDescription.fulfill()
        }

        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)

        self.checkRoomExists(roomName: roomName, withAccount: activeAccount) { room in
            XCTAssertEqual(room?.roomDescription, roomDescription)
        }
    }

    func testRoomRename() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomName = "Rename Test Room"
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
            expNewName.fulfill()
        }

        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)

        self.checkRoomExists(roomName: roomNameNew, withAccount: activeAccount) { room in
            XCTAssertEqual(room?.displayName, roomNameNew)
        }
    }
}
