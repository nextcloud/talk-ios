//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

final class CarPlayConversationProvider {
    static let shared = CarPlayConversationProvider()

    private init() {}

    func conversations() -> [NCRoom] {
        let account = NCDatabaseManager.sharedInstance().activeAccount()

        return NCDatabaseManager.sharedInstance()
            .roomsForAccountId(account.accountId, withRealm: nil)
            .filter { $0.isVisible && !$0.isArchived }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    /// Favorite one-to-one Talk rooms exposed as direct call targets.
    func speedDial() -> [NCRoom] {
        callableRooms()
            .filter(\.isFavorite)
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    /// Recent one-to-one Talk rooms exposed in the CarPlay Calls tab.
    func callHistory() -> [NCRoom] {
        callableRooms()
            .filter(\.isOneToOne)
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    func room(withToken token: String) -> NCRoom? {
        let account = NCDatabaseManager.sharedInstance().activeAccount()

        return NCDatabaseManager.sharedInstance().room(
            withToken: token,
            forAccountId: account.accountId
        )
    }

    private func callableRooms() -> [NCRoom] {
        let account = NCDatabaseManager.sharedInstance().activeAccount()

        return NCDatabaseManager.sharedInstance()
            .roomsForAccountId(account.accountId, withRealm: nil)
            .filter { room in
                room.isVisible &&
                    !room.isArchived &&
                    room.supportsCalling &&
                    room.userCanStartCall
            }
            .sorted { $0.lastActivity > $1.lastActivity }
    }
}
