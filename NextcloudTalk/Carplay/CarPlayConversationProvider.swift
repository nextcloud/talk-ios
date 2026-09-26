//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

final class CarPlayConversationProvider {

    static let shared = CarPlayConversationProvider()

    private init() {}

    func conversations() -> [NCRoom] {
        callableRooms()
    }

    /// Teams-like "Speed Dial" source.
    ///
    /// Talk already has a native Favorites concept, so CarPlay uses favorite
    /// callable conversations as the user's speed-dial list. A favorite phone
    /// room remains a PSTN destination while a favorite Talk room remains a
    /// native Talk destination; NCCallRouter decides which path to use.
    func speedDial() -> [NCRoom] {
        callableRooms()
            .filter(\.isFavorite)
            .sorted { first, second in
                first.lastActivity > second.lastActivity
            }
    }

    /// Recent callable destinations for the CarPlay Calls tab.
    ///
    /// This intentionally models destinations, not SIP details. One-to-one
    /// Talk rooms and phone rooms are useful direct call targets. Group rooms
    /// stay available in the Conversations tab but are not presented as call
    /// history entries.
    func callHistory() -> [NCRoom] {
        callableRooms()
            .filter { room in
                room.isOneToOne || NCTelephonyManager.shared.isPhoneRoom(room)
            }
            .sorted { first, second in
                first.lastActivity > second.lastActivity
            }
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

        let rooms = NCDatabaseManager.sharedInstance().roomsForAccountId(
            account.accountId,
            withRealm: nil
        )

        return rooms
            .filter { room in
                guard room.isVisible, !room.isArchived else {
                    return false
                }

                // Phone rooms are dialable through our PSTN bridge. Native
                // Talk rooms must satisfy the normal Talk calling rules.
                if NCTelephonyManager.shared.isPhoneRoom(room) {
                    return true
                }

                return room.supportsCalling && room.userCanStartCall
            }
            .sorted { first, second in
                first.lastActivity > second.lastActivity
            }
    }
}
