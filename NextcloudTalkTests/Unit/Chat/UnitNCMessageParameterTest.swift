//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitNCMessageParameterTest: XCTestCase {

    func testMentionIdFromServerLocal() throws {
        let data = [
            "id": "admin",
            "mention-id": "admin",
            "name": "admin displayname",
            "type": "user"
        ]

        let parameters = NCMessageParameter(dictionary: data)

        guard let parameters else {
            XCTFail("Failed to create message parameters with dictionary")
            return
        }

        XCTAssertEqual(parameters.parameterId, "admin")
        XCTAssertEqual(parameters.name, "admin displayname")
        XCTAssertEqual(parameters.mention?.id, "admin")
        XCTAssertEqual(parameters.mention?.idForChat, "@\"admin\"")
        XCTAssertEqual(parameters.mention?.label, "admin displayname")
        XCTAssertEqual(parameters.mention?.labelForChat, "@admin displayname")
    }

    func testMentionIdFromServerFederated() throws {
        let data = [
            "id": "admin",
            "mention-id": "federated_user/admin@nextcloud.local",
            "name": "admin displayname",
            "server": "https://nextcloud.local",
            "type": "user"
        ]

        let parameters = NCMessageParameter(dictionary: data)

        guard let parameters else {
            XCTFail("Failed to create message parameters with dictionary")
            return
        }

        XCTAssertEqual(parameters.parameterId, "admin")
        XCTAssertEqual(parameters.name, "admin displayname")
        XCTAssertEqual(parameters.mention?.idForChat, "@\"federated_user/admin@nextcloud.local\"")
    }

}
