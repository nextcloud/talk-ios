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
import Foundation
@testable import NextcloudTalk

final class IntegrationRoomsManagerTest: TestBase {

    func testJoinNonExistantRoom() throws {
        let roomToken = "nonexistantToken"

        expectation(forNotification: .NCRoomsManagerDidJoinRoom, object: nil) { notification -> Bool in
            XCTAssertEqual(NCRoomsManager.sharedInstance().joiningAttempts, 3)

            XCTAssertNotNil(notification.userInfo?["error"])
            XCTAssertNotNil(notification.userInfo?["statusCode"])
            XCTAssertNotNil(notification.userInfo?["errorReason"])

            // swiftlint:disable:next force_cast
            XCTAssertEqual(notification.userInfo?["token"] as! String, roomToken)

            // There's no NCRoomController when joining fails
            XCTAssertNil(notification.userInfo?["roomController"])

            return true
        }

        NCRoomsManager.sharedInstance().joinRoom(roomToken, forCall: false)

        waitForExpectations(timeout: TestConstants.timeoutShort)
    }

    func testJoinLeaveExistantRoom() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        var roomToken = ""

        let exp = expectation(description: "\(#function)\(#line)")

        // Create a room
        NCAPIController.sharedInstance().createRoom(forAccount: activeAccount, withInvite: nil, ofType: .public, andName: "Test Join Room") { room, error in
            XCTAssertNil(error)

            roomToken = room?.token ?? ""

            exp.fulfill()
        }

        waitForExpectations(timeout: TestConstants.timeoutShort, handler: nil)

        // Setup expectations for the DidJoinRoom notification
        expectation(forNotification: .NCRoomsManagerDidJoinRoom, object: nil) { notification -> Bool in
            XCTAssertEqual(NCRoomsManager.sharedInstance().joiningAttempts, 0)

            XCTAssertNil(notification.userInfo?["error"])
            XCTAssertNil(notification.userInfo?["statusCode"])
            XCTAssertNil(notification.userInfo?["errorReason"])

            // swiftlint:disable:next force_cast
            XCTAssertEqual(notification.userInfo?["token"] as! String, roomToken)

            // Check if the NCRoomController was correctly added to the activeRooms dictionary
            XCTAssertNotNil(NCRoomsManager.sharedInstance().activeRooms[roomToken])

            // When successfully joined, the NCRoomController should be included in the notification
            XCTAssertNotNil(notification.userInfo?["roomController"])

            return true
        }

        // Try to join the room
        NCRoomsManager.sharedInstance().joinRoom(roomToken, forCall: false)

        waitForExpectations(timeout: TestConstants.timeoutShort)

        // Setup expectations for the DidLeaveRoom notification
        expectation(forNotification: .NCRoomsManagerDidLeaveRoom, object: nil) { notification -> Bool in
            XCTAssertNil(notification.userInfo?["error"])

            // Check if the NCRoomController was correctly removed from the activeRooms dictionary
            XCTAssertNil(NCRoomsManager.sharedInstance().activeRooms[roomToken])

            return true
        }

        // Try to leave the room
        NCRoomsManager.sharedInstance().leaveChat(inRoom: roomToken)

        waitForExpectations(timeout: TestConstants.timeoutShort)
    }

}
