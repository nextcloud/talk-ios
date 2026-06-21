//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Testing
@testable import NextcloudTalk

struct UnitNCChatMessageHeightCache {

    @Test func `message height cache`() throws {
        let cache = NCChatMessageHeightCache()

        let message1 = NCChatMessage()
        message1.messageId = 123

        let message2 = NCChatMessage()
        message2.messageId = 345

        cache.setHeight(forMessage: message1, forWidth: 100, withHeight: 50)
        cache.setHeight(forMessage: message2, forWidth: 100, withHeight: 60)
        #expect(cache.getHeight(forMessage: message1, forWidth: 100) == 50)
        #expect(cache.getHeight(forMessage: message2, forWidth: 100) == 60)

        cache.setHeight(forMessage: message1, forWidth: 200, withHeight: 70)
        #expect(cache.getHeight(forMessage: message1, forWidth: 200) == 70)

        #expect(cache.getHeight(forMessage: message1, forWidth: 100) == nil)
        #expect(cache.getHeight(forMessage: message2, forWidth: 100) == nil)
        #expect(cache.getHeight(forMessage: message2, forWidth: 200) == nil)

        cache.setHeight(forMessage: message2, forWidth: 200, withHeight: 80)
        cache.removeHeight(forMessage: message1)
        #expect(cache.getHeight(forMessage: message1, forWidth: 200) == nil)
        #expect(cache.getHeight(forMessage: message2, forWidth: 200) == 80)
    }

}
