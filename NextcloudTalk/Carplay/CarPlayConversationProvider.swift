//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

final class CarPlayConversationProvider {

    static let shared = CarPlayConversationProvider()

    private init() {}

    func callableRooms() -> [NCRoom] {
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

    func speedDial() -> [NCRoom] {
        callableRooms()
            .filter(\.isFavorite)
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    func room(withToken token: String) -> NCRoom? {
        let account = NCDatabaseManager.sharedInstance().activeAccount()

        return NCDatabaseManager.sharedInstance().room(
            withToken: token,
            forAccountId: account.accountId
        )
    }
}
