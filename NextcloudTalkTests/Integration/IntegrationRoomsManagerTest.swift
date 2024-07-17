//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
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

            // swiftlint:disable:next force_cast
            XCTAssertEqual(notification.userInfo?["token"] as! String, roomToken)

            // Check if the NCRoomController was correctly removed from the activeRooms dictionary
            XCTAssertNil(NCRoomsManager.sharedInstance().activeRooms[roomToken])

            return true
        }

        // Try to leave the room
        NCRoomsManager.sharedInstance().leaveChat(inRoom: roomToken)

        waitForExpectations(timeout: TestConstants.timeoutShort)
    }

}
