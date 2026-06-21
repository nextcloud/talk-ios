//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Testing
@testable import NextcloudTalk

@Suite(.serialized)
final class UnitMessageBodyTextViewTest: TestBaseRealm {

    @Test func `cell with markdown quote height`() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let testMessage = NCChatMessage(dictionary: [:], andAccountId: activeAccount.accountId)!

        // Markdown message
        testMessage.message = "> 1234567890123456789012345678"
        testMessage.isMarkdownMessage = true

        let messageTextView = MessageBodyTextView()
        messageTextView.attributedText = testMessage.parsedMarkdownForChat()

        #expect(messageTextView.intrinsicContentSize == CGSize(width: 259, height: 20))
    }

}
