//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitNCDatabaseManager: TestBaseRealm {

    func testSavingExternalSignalingVersion() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let testVersion = "Test version"
        let testVersionUpdated = "Test version updated"

        updateCapabilities { cap in
            cap.externalSignalingServerVersion = testVersion
        }

        var capabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId)
        XCTAssertEqual(capabilities?.externalSignalingServerVersion, testVersion)

        NCDatabaseManager.sharedInstance().setExternalSignalingServerVersion(testVersionUpdated, forAccountId: activeAccount.accountId)

        capabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId)
        XCTAssertEqual(capabilities?.externalSignalingServerVersion, testVersionUpdated)
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
        let rooms = NCDatabaseManager.sharedInstance().roomsForAccountId(activeAccount.accountId, withRealm: nil)
        let expectedOrder = [favNew, favOld, nonFavNew, nonFavOld]

        XCTAssertEqual(rooms.count, 4)

        // Check if the order is correct
        for (index, element) in rooms.enumerated() {
            XCTAssertEqual(expectedOrder[index].token, element.token)
        }
    }
}
