//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitNCPeerConnectionTest: XCTestCase {

    private let sessionLines = [
        "v=0",
        "o=- 4611731400430051336 2 IN IP4 127.0.0.1",
        "s=-",
        "t=0 0",
        "a=group:BUNDLE 0 1 2"
    ]

    private let audioLines = [
        "m=audio 9 UDP/TLS/RTP/SAVPF 111",
        "c=IN IP4 0.0.0.0",
        "a=mid:0",
        "a=sendonly",
        "a=rtpmap:111 opus/48000/2"
    ]

    private let dataLines = [
        "m=application 9 UDP/DTLS/SCTP webrtc-datachannel",
        "c=IN IP4 0.0.0.0",
        "a=mid:2"
    ]

    private func videoLines(rids: [String], simulcast: String?) -> [String] {
        var lines = [
            "m=video 9 UDP/TLS/RTP/SAVPF 96 97 98",
            "c=IN IP4 0.0.0.0",
            "a=mid:1",
            "a=extmap:10 urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id",
            "a=extmap:11 urn:ietf:params:rtp-hdrext:sdes:repaired-rtp-stream-id",
            "a=sendonly",
            "a=rtpmap:96 VP8/90000",
            "a=rtpmap:97 rtx/90000",
            "a=fmtp:97 apt=96"
        ]

        lines += rids.map { "a=rid:\($0)" }

        if let simulcast {
            lines.append("a=simulcast:send \(simulcast)")
        }

        return lines
    }

    private func sdp(video: [String]) -> String {
        // Like libwebrtc, every line including the last one is terminated by CRLF
        return (sessionLines + audioLines + video + dataLines).joined(separator: "\r\n") + "\r\n"
    }

    func testSimulcastLayersAreReversedForTheMCU() throws {
        let offer = sdp(video: videoLines(rids: ["l send", "m send", "h send"], simulcast: "l;m;h"))
        let expected = sdp(video: videoLines(rids: ["h send", "m send", "l send"], simulcast: "h;m;l"))

        XCTAssertEqual(NCPeerConnection.sdpWithReversedSimulcastLayers(offer), expected)
    }

    func testPausedLayerKeepsItsMarker() throws {
        let offer = sdp(video: videoLines(rids: ["l send", "m send", "h send"], simulcast: "~l;m;h"))
        let expected = sdp(video: videoLines(rids: ["h send", "m send", "l send"], simulcast: "h;m;~l"))

        XCTAssertEqual(NCPeerConnection.sdpWithReversedSimulcastLayers(offer), expected)
    }

    func testRidParametersMoveWithTheirLayer() throws {
        let offer = sdp(video: videoLines(rids: ["l send pt=96", "m send", "h send max-width=1280;max-height=720"], simulcast: "l;m;h"))
        let expected = sdp(video: videoLines(rids: ["h send max-width=1280;max-height=720", "m send", "l send pt=96"], simulcast: "h;m;l"))

        XCTAssertEqual(NCPeerConnection.sdpWithReversedSimulcastLayers(offer), expected)
    }

    func testOfferWithoutSimulcastIsUnchanged() throws {
        let offer = sdp(video: videoLines(rids: [], simulcast: nil))

        XCTAssertEqual(NCPeerConnection.sdpWithReversedSimulcastLayers(offer), offer)
    }
}
