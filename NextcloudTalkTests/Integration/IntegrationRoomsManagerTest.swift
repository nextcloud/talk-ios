//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Testing
@testable import NextcloudTalk

@Suite(.serialized)
final class IntegrationRoomsManagerTest: TestBase {

    @Test func `join non existant room`() async {
        let roomToken = "nonexistantToken"

        let joinTracker = EventTracker()
        let observer = NotificationCenter.default.addObserver(forName: .NCRoomsManagerDidJoinRoom, object: nil, queue: nil) { notification in
            #expect(NCRoomsManager.shared.joiningAttempts == 3)

            #expect(notification.userInfo?["error"] != nil)
            #expect(notification.userInfo?["statusCode"] != nil)
            #expect(notification.userInfo?["errorReason"] != nil)

            #expect(notification.userInfo?["token"] as? String == roomToken)

            // There's no NCRoomController when joining fails
            #expect(notification.userInfo?["roomController"] == nil)

            joinTracker.signal()
        }

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCRoomsManager.shared.joinRoom(roomToken, forAccountId: activeAccount.accountId, forCall: false)

        let joinFailed = await wait(timeout: TestConstants.timeoutShort) { joinTracker.fired }
        NotificationCenter.default.removeObserver(observer)
        #expect(joinFailed)
    }

    @Test func `join leave existant room`() async {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        // Create a room
        let roomToken: String = await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().createRoom(forAccount: activeAccount, withInvite: nil, ofType: .public, andName: "Test Join Room") { room, error in
                #expect(error == nil)
                continuation.resume(returning: room?.token ?? "")
            }
        }

        // Observe the DidJoinRoom notification
        let joinTracker = EventTracker()
        let joinObserver = NotificationCenter.default.addObserver(forName: .NCRoomsManagerDidJoinRoom, object: nil, queue: nil) { notification in
            #expect(NCRoomsManager.shared.joiningAttempts == 0)

            #expect(notification.userInfo?["error"] == nil)
            #expect(notification.userInfo?["statusCode"] == nil)
            #expect(notification.userInfo?["errorReason"] == nil)

            #expect(notification.userInfo?["token"] as? String == roomToken)

            // Check if the NCRoomController was correctly added to the activeRooms dictionary
            #expect(NCRoomsManager.shared.activeRooms[roomToken] != nil)

            // When successfully joined, the NCRoomController should be included in the notification
            #expect(notification.userInfo?["roomController"] != nil)

            joinTracker.signal()
        }

        // Try to join the room
        NCRoomsManager.shared.joinRoom(roomToken, forAccountId: activeAccount.accountId, forCall: false)

        let joined = await wait(timeout: TestConstants.timeoutShort) { joinTracker.fired }
        NotificationCenter.default.removeObserver(joinObserver)
        #expect(joined)

        // Observe the DidLeaveRoom notification
        let leaveTracker = EventTracker()
        let leaveObserver = NotificationCenter.default.addObserver(forName: .NCRoomsManagerDidLeaveRoom, object: nil, queue: nil) { notification in
            #expect(notification.userInfo?["error"] == nil)

            #expect(notification.userInfo?["token"] as? String == roomToken)

            // Check if the NCRoomController was correctly removed from the activeRooms dictionary
            #expect(NCRoomsManager.shared.activeRooms[roomToken] == nil)

            leaveTracker.signal()
        }

        // Try to leave the room
        NCRoomsManager.shared.leaveChat(inRoom: roomToken, forAccount: activeAccount)

        let left = await wait(timeout: TestConstants.timeoutShort) { leaveTracker.fired }
        NotificationCenter.default.removeObserver(leaveObserver)
        #expect(left)
    }

}
