//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Testing
@testable import NextcloudTalk

@MainActor
class TestBaseRealm {

    static let fakeAccountId = "fakeAccountId"
    var realm: RLMRealm

    init() {
        // Setup in memory database
        let config = RLMRealmConfiguration()
        // Use a UUID to create a new/empty database for each test
        config.inMemoryIdentifier = UUID().uuidString

        RLMRealmConfiguration.setDefault(config)

        realm = RLMRealm.default()

        createFakeActiveAccount()
    }

    deinit {
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

    /// A small reference-type helper to observe events fired from escaping notification or completion handlers.
    final class EventTracker {
        private(set) var signalCount = 0
        var fired: Bool { signalCount > 0 }
        func signal() { signalCount += 1 }
    }

    /// Pumps the run loop until `condition` is satisfied or the timeout elapses.
    /// Useful for events delivered asynchronously via the run loop (NSNotification) or dispatch queues.
    /// Returns `true` if the condition was satisfied before the timeout.
    @discardableResult
    func wait(timeout: TimeInterval = TestConstants.timeoutShort, until condition: () -> Bool) async -> Bool {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) >= timeout {
                return false
            }
            try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
        }
        return true
    }
}
