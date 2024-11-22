//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitNCChatMessageTest: TestBaseRealm {

    func testUnreadMessageSeparatorUrlCheck() throws {
        let message = NCChatMessage()
        message.messageId = MessageSeparatorTableViewCell.unreadMessagesSeparatorId

        updateCapabilities { cap in
            cap.referenceApiSupported = true
        }

        XCTAssertFalse(message.containsURL())
    }

}
