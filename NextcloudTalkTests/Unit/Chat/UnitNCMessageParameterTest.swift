//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
@testable import NextcloudTalk

struct UnitNCMessageParameterTest {

    @Test func `mention id from server local`() throws {
        let data = [
            "id": "admin",
            "mention-id": "admin",
            "name": "admin displayname",
            "type": "user"
        ]

        let parameters = try #require(NCMessageParameter(dictionary: data), "Failed to create message parameters with dictionary")

        #expect(parameters.parameterId == "admin")
        #expect(parameters.name == "admin displayname")
        #expect(parameters.mention?.id == "admin")
        #expect(parameters.mention?.idForChat == "@\"admin\"")
        #expect(parameters.mention?.label == "admin displayname")
        #expect(parameters.mention?.labelForChat == "@admin displayname")
    }

    @Test func `mention id from server federated`() throws {
        let data = [
            "id": "admin",
            "mention-id": "federated_user/admin@nextcloud.local",
            "name": "admin displayname",
            "server": "https://nextcloud.local",
            "type": "user"
        ]

        let parameters = try #require(NCMessageParameter(dictionary: data), "Failed to create message parameters with dictionary")

        #expect(parameters.parameterId == "admin")
        #expect(parameters.name == "admin displayname")
        #expect(parameters.mention?.idForChat == "@\"federated_user/admin@nextcloud.local\"")
    }

    @Test func `file message parameter`() throws {
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
        let messageParameterDict = try #require([String: NCMessageParameter].fromJSONString(jsonData))
        #expect(messageParameterDict.count == 2)

        let fileParameter = try #require(messageParameterDict["file"])
        #expect(fileParameter.parameterId == "6160")
        #expect(fileParameter.name == "IMG_0111 (13).jpg")

        let message = NCChatMessage()
        message.messageParametersJSONString = jsonData

        let messageFile = try #require(message.file())

        #expect(messageFile.size == 4127524)
        #expect(messageFile.path == "Talk/IMG_0111 (13).jpg")
        #expect(messageFile.mimetype == "image/jpeg")
        #expect(messageFile.previewAvailable == true)
        #expect(messageFile.previewAvailable == true)
        #expect(messageFile.width == 4032)
        #expect(messageFile.height == 3024)
        #expect(messageFile.blurhash == "LBC;@m%$%itT?d?J-=-;Q3-=%Np0")
    }

    @Test func `legacy file message parameter`() throws {
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

        let messageFile = try #require(message.file())

        #expect(messageFile.parameterId == "6160")
        #expect(messageFile.size == 4127524)
        #expect(messageFile.path == "Talk/IMG_0111 (13).jpg")
        #expect(messageFile.mimetype == "image/jpeg")
        #expect(messageFile.previewAvailable == true)
        #expect(messageFile.previewAvailable == true)
        #expect(messageFile.width == 4032)
        #expect(messageFile.height == 3024)
        #expect(messageFile.blurhash == "LBC;@m%$%itT?d?J-=-;Q3-=%Np0")
    }

}
