//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

class TestBaseRealm: XCTestCase {

    static var fakeAccountId = "fakeAccountId"
    var realm: RLMRealm!

    override func setUpWithError() throws {
        // Setup in memory database
        let config = RLMRealmConfiguration()
        // Use a UUID to create a new/empty database for each test
        config.inMemoryIdentifier = UUID().uuidString

        RLMRealmConfiguration.setDefault(config)

        realm = RLMRealm.default()

        createFakeActiveAccount()
    }

    override func tearDownWithError() throws {
        // Make sure we correctly remove the fake account again, to clear the capability cache in NCDatabaseManager
        NCDatabaseManager.sharedInstance().removeAccount(withAccountId: TestBaseRealm.fakeAccountId)
    }

    func createFakeActiveAccount() {
        let account = TalkAccount()
        account.accountId = TestBaseRealm.fakeAccountId
        account.active = true
        account.user = TestConstants.username
        account.server = TestConstants.server

        try? realm.transaction {
            realm.add(account)
        }
    }

    func updateCapabilities(updateBlock: @escaping (ServerCapabilities) -> Void) {
        try? realm.transaction {
            var capabilities = ServerCapabilities()
            capabilities.accountId = TestBaseRealm.fakeAccountId

            if let storedCapabilities = ServerCapabilities.object(forPrimaryKey: TestBaseRealm.fakeAccountId) {
                capabilities = storedCapabilities
            }

            updateBlock(capabilities)
            realm.addOrUpdate(capabilities)
        }
    }

    @discardableResult
    func addRoom(withToken roomToken: String, withName roomName: String = "", withAccountId accountId: String = fakeAccountId, updateBlock: ((NCRoom) -> Void)? = nil) -> NCRoom {
        let room = NCRoom()
        room.token = roomToken
        room.name = roomName
        room.accountId = accountId
        room.internalId = "\(roomToken)@\(accountId)"
        updateBlock?(room)

        try? realm.transaction {
            realm.add(room)
        }

        return room
    }
}
