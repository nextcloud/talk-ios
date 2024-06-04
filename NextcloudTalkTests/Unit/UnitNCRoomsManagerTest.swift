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
@testable import NextcloudTalk

final class UnitNCRoomsManagerTest: TestBaseRealm {

    func testOfflineMessageFailure() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomToken = "offToken"

        addRoom(withToken: roomToken)

        // Create 2 messages which are in different sections
        let oldOfflineMessage = NCChatMessage()

        oldOfflineMessage.internalId = "internal1"
        oldOfflineMessage.accountId = activeAccount.accountId
        oldOfflineMessage.actorDisplayName = activeAccount.userDisplayName
        oldOfflineMessage.actorId = activeAccount.userId
        oldOfflineMessage.actorType = "users"
        oldOfflineMessage.token = roomToken
        oldOfflineMessage.message = "Message 1"
        oldOfflineMessage.isOfflineMessage = true
        oldOfflineMessage.sendingFailed = false

        // 12h is the threshold, set it to 13 hours
        oldOfflineMessage.timestamp = Int(Date().timeIntervalSince1970) - (60 * 60 * 13)

        try? realm.transaction {
            realm.add(oldOfflineMessage)
        }

        XCTAssertEqual(NCChatMessage.allObjects().count, 1)

        let exp = expectation(description: "\(#function)\(#line)")
        expectation(forNotification: .NCChatControllerDidSendChatMessage, object: NCRoomsManager.sharedInstance())

        NCRoomsManager.sharedInstance().resendOfflineMessages(forToken: roomToken) {
            exp.fulfill()
        }

        waitForExpectations(timeout: TestConstants.timeoutShort, handler: nil)

        let realmMessage = NCChatMessage.allObjects().firstObject()!
        XCTAssertTrue(realmMessage.sendingFailed)
        XCTAssertFalse(realmMessage.isOfflineMessage)
    }

    func testRoomsForAccount() throws {
        let nonFavOld = addRoom(withToken: "NonFavOld") { room in
            room.lastActivity = 100
        }

        let nonFavNew = addRoom(withToken: "NonFavNew") { room in
            room.lastActivity = 1000
        }

        let favOld = addRoom(withToken: "FavOld") { room in
            room.lastActivity = 100
            room.isFavorite = true
        }

        let favNew = addRoom(withToken: "FavNew") { room in
            room.lastActivity = 1000
            room.isFavorite = true
        }

        // Add an unrelated room, which should not be returned
        addRoom(withToken: "Unrelated", withAccountId: "foo")

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let rooms = NCRoomsManager.sharedInstance().roomsForAccountId(activeAccount.accountId, withRealm: nil)
        let expectedOrder = [favNew, favOld, nonFavNew, nonFavOld]

        XCTAssertEqual(rooms.count, 4)

        // Check if the order is correct
        for (index, element) in rooms.enumerated() {
            XCTAssertEqual(expectedOrder[index].token, element.token)
        }
    }
}
