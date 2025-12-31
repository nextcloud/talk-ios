//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitMessageBodyTextViewTest: TestBaseRealm {

    func testCellWithMarkdownQuoteHeight() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let testMessage = NCChatMessage(dictionary: [:], andAccountId: activeAccount.accountId)!

        // Markdown message
        testMessage.message = "> 1234567890123456789012345678"
        testMessage.isMarkdownMessage = true

        let messageTextView = MessageBodyTextView()
        messageTextView.attributedText = testMessage.parsedMarkdownForChat()

        XCTAssertEqual(messageTextView.intrinsicContentSize, CGSize(width: 259, height: 20))
    }

}
