//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitNCChatMessageHeightCache: XCTestCase {

    func testMessageHeightCache() throws {
        let cache = NCChatMessageHeightCache()

        let message1 = NCChatMessage()
        message1.messageId = 123

        let message2 = NCChatMessage()
        message2.messageId = 345

        cache.setHeight(forMessage: message1, forWidth: 100, withHeight: 50)
        cache.setHeight(forMessage: message2, forWidth: 100, withHeight: 60)
        XCTAssertEqual(cache.getHeight(forMessage: message1, forWidth: 100), 50)
        XCTAssertEqual(cache.getHeight(forMessage: message2, forWidth: 100), 60)

        cache.setHeight(forMessage: message1, forWidth: 200, withHeight: 70)
        XCTAssertEqual(cache.getHeight(forMessage: message1, forWidth: 200), 70)

        XCTAssertNil(cache.getHeight(forMessage: message1, forWidth: 100))
        XCTAssertNil(cache.getHeight(forMessage: message2, forWidth: 100))
        XCTAssertNil(cache.getHeight(forMessage: message2, forWidth: 200))

        cache.setHeight(forMessage: message2, forWidth: 200, withHeight: 80)
        cache.removeHeight(forMessage: message1)
        XCTAssertNil(cache.getHeight(forMessage: message1, forWidth: 200))
        XCTAssertEqual(cache.getHeight(forMessage: message2, forWidth: 200), 80)
    }

}
