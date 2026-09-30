//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
import WebRTC
@testable import NextcloudTalk

// Checks the frame encryption API of the WebRTC framework the app ships, the frame format itself is tested
// in talk-clients-webrtc
final class UnitTalkKeyRingTest: XCTestCase {

    private let key = Data(0..<32)

    func testRatchetKeyMatchesWebClient() {
        // What spreed's crypto-utils.js ratchet() derives from the same key
        let expected = Data([
            0xcd, 0x44, 0x1c, 0xd8, 0x85, 0xa6, 0xd2, 0x8c, 0xe0, 0x3c, 0xe2, 0xca, 0x30, 0xff, 0x7f, 0x3a,
            0xf9, 0x35, 0x96, 0xa0, 0x9c, 0xa7, 0xc7, 0x82, 0xa9, 0xa0, 0x5e, 0x07, 0xe8, 0x02, 0x54, 0xee
        ])

        XCTAssertEqual(RTCTalkKeyRing.ratchetKey(key), expected)
    }

    func testIgnoresEmptyKey() {
        let keyRing = RTCTalkKeyRing()

        XCTAssertFalse(keyRing.setKey(Data(), at: 0))
        XCTAssertTrue(keyRing.setKey(key, at: 0))
        XCTAssertNil(RTCTalkKeyRing.ratchetKey(Data()))
    }

    // The native encryptor is not visible through the public API, this checks the calls are linked and go through
    func testAttachesAndDetachesKeyRing() throws {
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

        let peerConnection = try XCTUnwrap(WebRTCCommon.shared.peerConnectionFactory.peerConnection(with: config, constraints: constraints, delegate: nil))
        defer { peerConnection.close() }

        let keyRing = RTCTalkKeyRing()
        keyRing.setKey(key, at: 0)

        for mediaType in [RTCRtpMediaType.audio, .video] {
            let transceiver = try XCTUnwrap(peerConnection.addTransceiver(of: mediaType))

            transceiver.sender.setTalkKeyRing(keyRing)
            transceiver.receiver.setTalkKeyRing(keyRing)
            transceiver.sender.setTalkKeyRing(nil)
            transceiver.receiver.setTalkKeyRing(nil)
        }
    }
}
