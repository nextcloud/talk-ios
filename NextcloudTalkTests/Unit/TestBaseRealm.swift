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

class TestBaseRealm: XCTestCase {

    let fakeAccountId = "fakeAccountId"
    var realm: RLMRealm!

    override func setUpWithError() throws {
        // Setup in memory database
        let config = RLMRealmConfiguration()
        // Use a UUID to create a new/empty database for each test
        config.inMemoryIdentifier = UUID().uuidString
        config.objectClasses = [TalkAccount.self, NCChatMessage.self, NCRoom.self, ServerCapabilities.self]

        RLMRealmConfiguration.setDefault(config)

        realm = RLMRealm.default()

        createFakeActiveAccount()
    }

    func createFakeActiveAccount() {
        let account = TalkAccount()
        account.accountId = fakeAccountId
        account.active = true

        try? realm.transaction {
            realm.add(account)
        }
    }

    func updateCapabilities(updateBlock: @escaping (ServerCapabilities) -> Void) {
        let capabilities = ServerCapabilities()
        capabilities.accountId = fakeAccountId
        updateBlock(capabilities)

        try? realm.transaction {
            realm.add(capabilities)
        }
    }
}
