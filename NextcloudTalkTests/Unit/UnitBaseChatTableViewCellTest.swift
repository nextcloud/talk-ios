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
        deckCell.setup(for: deckMessage, withLastCommonReadMessage: 0)

        let quoteCell: BaseChatTableViewCell = .fromNib()
        quoteCell.setup(for: quoteMessage, withLastCommonReadMessage: 0)
    }

}
