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

    func testFileMessageParameter() throws {
        let jsonData = """
        {
            "actor": {
                "type": "user",
                "id": "admin",
                "name": "admin",
                "mention-id": "admin"
            },
            "file": {
                "type": "file",
                "id": "6160",
                "name": "IMG_0111 (13).jpg",
                "size": "4127524",
                "path": "Talk\\/IMG_0111 (13).jpg",
                "link": "https:\\/\\/nextcloud-mm.internal\\/index.php\\/f\\/6160",
                "etag": "a1ae070fe0f2560d72f7b6beb79f3d3d",
                "permissions": "27",
                "mimetype": "image\\/jpeg",
                "preview-available": "yes",
                "hide-download": "no",
                "width": "4032",
                "height": "3024",
                "blurhash": "LBC;@m%$%itT?d?J-=-;Q3-=%Np0"
            }
        }
        """

        // Parse as NCMessageParameter, does not take something like NCFileMessageParameter into account
        let messageParameterDict = try XCTUnwrap([String: NCMessageParameter].fromJSONString(jsonData))
        XCTAssertEqual(messageParameterDict.count, 2)

        let fileParameter = try XCTUnwrap(messageParameterDict["file"])
        XCTAssertEqual(fileParameter.parameterId, "6160")
        XCTAssertEqual(fileParameter.name, "IMG_0111 (13).jpg")

        let message = NCChatMessage()
        message.messageParametersJSONString = jsonData

        let messageFile = try XCTUnwrap(message.file())

        XCTAssertEqual(messageFile.size, 4127524)
        XCTAssertEqual(messageFile.path, "Talk/IMG_0111 (13).jpg")
        XCTAssertEqual(messageFile.mimetype, "image/jpeg")
        XCTAssertEqual(messageFile.previewAvailable, true)
        XCTAssertEqual(messageFile.previewAvailable, true)
        XCTAssertEqual(messageFile.width, 4032)
        XCTAssertEqual(messageFile.height, 3024)
        XCTAssertEqual(messageFile.blurhash, "LBC;@m%$%itT?d?J-=-;Q3-=%Np0")
        XCTAssertEqual(messageFile.permissions, 27)
        XCTAssertTrue(messageFile.canBeShared)
    }

    func testFileMessageParameterRightToShare() throws {
        func fileParameter(permissions: String?) throws -> NCMessageFileParameter {
            let permissionsEntry = permissions.map { "\"permissions\": \"\($0)\"," } ?? ""
            let message = NCChatMessage()
            message.messageParametersJSONString = """
            { "file": { "type": "file", "id": "6160", "name": "a.jpg", \(permissionsEntry) "path": "a.jpg" } }
            """
            return try XCTUnwrap(message.file())
        }

        // Read, update, delete and share
        XCTAssertTrue(try fileParameter(permissions: "27").canBeShared)
        // Read, update and share
        XCTAssertTrue(try fileParameter(permissions: "19").canBeShared)
        // Read and update only, e.g. a file shared without reshare
        XCTAssertFalse(try fileParameter(permissions: "3").canBeShared)
        // Read and share, but no update: the server refuses the share with 403 "more permission"
        XCTAssertFalse(try fileParameter(permissions: "17").canBeShared)
        // Read only
        XCTAssertFalse(try fileParameter(permissions: "1").canBeShared)
        // The server did not tell: do not take away the action
        XCTAssertNil(try fileParameter(permissions: nil).permissions)
        XCTAssertTrue(try fileParameter(permissions: nil).canBeShared)
    }

    func testLegacyFileMessageParameter() throws {
        // In previous versions not all parameters were strings
        // See: https://github.com/nextcloud/spreed/pull/12021
        // See: https://github.com/nextcloud/spreed/pull/13200

        let jsonData = """
        {
            "file": {
                "type": "file",
                "id": 6160,
                "name": "IMG_0111 (13).jpg",
                "size": 4127524,
                "path": "Talk\\/IMG_0111 (13).jpg",
                "link": "https:\\/\\/nextcloud-mm.internal\\/index.php\\/f\\/6160",
                "etag": "a1ae070fe0f2560d72f7b6beb79f3d3d",
                "permissions": 27,
                "mimetype": "image\\/jpeg",
                "preview-available": "yes",
                "hide-download": "no",
                "width": 4032,
                "height": 3024,
                "blurhash": "LBC;@m%$%itT?d?J-=-;Q3-=%Np0"
            }
        }
        """

        let message = NCChatMessage()
        message.messageParametersJSONString = jsonData

        let messageFile = try XCTUnwrap(message.file())

        XCTAssertEqual(messageFile.parameterId, "6160")
        XCTAssertEqual(messageFile.size, 4127524)
        XCTAssertEqual(messageFile.path, "Talk/IMG_0111 (13).jpg")
        XCTAssertEqual(messageFile.mimetype, "image/jpeg")
        XCTAssertEqual(messageFile.previewAvailable, true)
        XCTAssertEqual(messageFile.previewAvailable, true)
        XCTAssertEqual(messageFile.width, 4032)
        XCTAssertEqual(messageFile.height, 3024)
        XCTAssertEqual(messageFile.blurhash, "LBC;@m%$%itT?d?J-=-;Q3-=%Np0")
    }

}
