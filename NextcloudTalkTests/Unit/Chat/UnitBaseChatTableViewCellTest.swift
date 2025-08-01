//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitBaseChatTableViewCellTest: TestBaseRealm {

    func testSharedDeckCardQuote() throws {
        let deckObject = """
{
    "actor": {
        "type": "user",
        "id": "admin",
        "name": "admin"
    },
    "object": {
        "id": "9810",
        "name": "Test",
        "boardname": "Persönlich",
        "stackname": "Offen",
        "link": "https://nextcloud-mm.local/apps/deck/card/9810",
        "type": "deck-card",
        "icon-url": "https://nextcloud-mm.local/ocs/v2.php/apps/spreed/api/v1/room/123/avatar?v=abc"
    }
}
"""

        updateCapabilities { cap in
            cap.referenceApiSupported = true
        }

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomToken = "token"

        let room = NCRoom()
        room.token = roomToken
        room.accountId = activeAccount.accountId

        let deckMessage = NCChatMessage()
        deckMessage.messageId = 1
        deckMessage.internalId = "internal-1"
        deckMessage.token = roomToken
        deckMessage.message = "existing"
        deckMessage.messageParametersJSONString = deckObject

        // Chat message with a quote
        let quoteMessage = NCChatMessage()
        quoteMessage.message = "test"
        quoteMessage.token = roomToken
        quoteMessage.parentId = "internal-1"

        try? realm.transaction {
            realm.add(room)
            realm.add(deckMessage)
            realm.add(quoteMessage)
        }

        let deckCell: BaseChatTableViewCell = .fromNib()
        deckCell.setup(for: deckMessage, inRoom: room, forThread: nil, withAccount: activeAccount)

        let quoteCell: BaseChatTableViewCell = .fromNib()
        quoteCell.setup(for: quoteMessage, inRoom: room, forThread: nil, withAccount: activeAccount)
    }

}
