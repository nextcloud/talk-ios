//
//  CarPlayConversationProvider.swift
//  NextcloudTalk
//
//  Created by Alexandre Martinez on 22/08/2026.
//

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

        let rooms = NCDatabaseManager.sharedInstance().roomsForAccountId(
            account.accountId,
            withRealm: nil
        )

        return rooms
            .filter { room in
                room.isVisible &&
                !room.isArchived &&
                room.supportsCalling &&
                room.userCanStartCall
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
}
