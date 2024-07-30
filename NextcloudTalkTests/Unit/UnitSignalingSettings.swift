//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitSignalingSettings: XCTestCase {

    func testSignalingSettings() throws {
        let dataJson =
        """
            {
                "signalingMode": "external",
                "userId": "test-user",
                "hideWarning": true,
                "server": "https://domain.invalid/standalone-signaling/",
                "ticket": "ticket:user:1234",
                "helloAuthParams": {
                    "1.0": {
                        "userid": "test-user",
                        "ticket": "helloauth1:ticket:user:1234"
                    },
                    "2.0": {
                        "token": "helloauth2:ticket:user:1234"
                    }
                },
                "stunservers": [
                    {
                        "urls": [
                            "stun:stun.domain.invalid:443"
                        ]
                    }
                ],
                "turnservers": [
                    {
                        "urls": [
                            "turn:turn.domain.invalid:443?transport=udp",
                            "turns:turn.domain.invalid:443?transport=udp"
                        ],
                        "username": "user:name",
                        "credential": "password"
                    }
                ],
            }
        """

        // swiftlint:disable:next force_cast
        let signalingDict = try JSONSerialization.jsonObject(with: dataJson.data(using: .utf8)!) as! [String: Any]
        let signalingSettings = SignalingSettings(dictionary: signalingDict)

        XCTAssertEqual(signalingSettings?.server, "https://domain.invalid/standalone-signaling/")
        XCTAssertEqual(signalingSettings?.signalingMode, "external")
        XCTAssertEqual(signalingSettings?.ticket, "ticket:user:1234")

        let stunServers = signalingSettings?.stunServers
        let turnServers = signalingSettings?.turnServers

        XCTAssertEqual(stunServers?.count, 1)
        XCTAssertEqual(stunServers?[0].urls?.count, 1)
        XCTAssertEqual(stunServers?[0].urls?[0], "stun:stun.domain.invalid:443")

        XCTAssertEqual(turnServers?.count, 1)
        XCTAssertEqual(turnServers?[0].urls?.count, 2)
        XCTAssertEqual(turnServers?[0].urls?[0], "turn:turn.domain.invalid:443?transport=udp")
        XCTAssertEqual(turnServers?[0].urls?[1], "turns:turn.domain.invalid:443?transport=udp")
        XCTAssertEqual(turnServers?[0].username, "user:name")
        XCTAssertEqual(turnServers?[0].credential, "password")
    }

    func testSignalingSettingsFederation() throws {
        let dataJson =
        """
            {
                "signalingMode": "external",
                "userId": "user",
                "hideWarning": true,
                "server": "https://domain.invalid/standalone-signaling",
                "ticket": "ticket:user:1234",
                "helloAuthParams": {
                    "1.0": {
                        "userid": "user",
                        "ticket": "helloauth1:ticket"
                    },
                    "2.0": {
                        "token": "helloauth2:ticket"
                    }
                },
                "federation": {
                    "server": "https://domain2.invalid/standalone-signaling",
                    "nextcloudServer": "https://nextcloud.domain2.invalid",
                    "helloAuthParams": {
                        "token": "federation:token"
                    },
                    "roomId": "federation:roomId"
                },
                "stunservers": [
                    {
                        "urls": [
                            "stun:stun.domain.invalid:443"
                        ]
                    }
                ],
                "turnservers": [
                    {
                        "urls": [
                            "turn:turn.domain.invalid:3478?transport=udp",
                            "turn:turn.domain.invalid:3478?transport=tcp"
                        ],
                        "username": "username",
                        "credential": "password"
                    }
                ],
            }
        """

        // swiftlint:disable:next force_cast
        let signalingDict = try JSONSerialization.jsonObject(with: dataJson.data(using: .utf8)!) as! [String: Any]
        let signalingSettings = SignalingSettings(dictionary: signalingDict)

        XCTAssertNotNil(signalingSettings?.federation)

        let federation = signalingSettings?.getFederationJoinDictionary()

        XCTAssertEqual(federation?["signaling"], "https://domain2.invalid/standalone-signaling")
        XCTAssertEqual(federation?["roomid"], "federation:roomId")
        XCTAssertEqual(federation?["url"], "https://nextcloud.domain2.invalid/ocs/v2.php/apps/spreed/api/v3/signaling/backend")
        XCTAssertEqual(federation?["token"], "federation:token")
    }

}
