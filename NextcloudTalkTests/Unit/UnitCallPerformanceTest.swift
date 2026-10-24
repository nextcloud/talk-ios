//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
import WebRTC
@testable import NextcloudTalk

final class UnitCallPerformanceTest: XCTestCase {

    func testMaxVideoQuality() {
        func maxVideoQuality(_ thermalState: ProcessInfo.ThermalState, _ lowPower: Bool) -> SimulcastVideoQuality {
            return CallPerformanceMonitor.maxVideoQuality(thermalState: thermalState, isLowPowerModeEnabled: lowPower).quality
        }

        XCTAssertEqual(maxVideoQuality(.nominal, false), .high)
        XCTAssertEqual(maxVideoQuality(.fair, false), .high)
        XCTAssertEqual(maxVideoQuality(.nominal, true), .medium)
        XCTAssertEqual(maxVideoQuality(.serious, false), .medium)
        XCTAssertEqual(maxVideoQuality(.serious, true), .medium)
        XCTAssertEqual(maxVideoQuality(.critical, false), .low)
        XCTAssertEqual(maxVideoQuality(.critical, true), .low)

        XCTAssertEqual(CallPerformanceMonitor.maxVideoQuality(thermalState: .serious, isLowPowerModeEnabled: true).reason, .thermalState)
        XCTAssertEqual(CallPerformanceMonitor.maxVideoQuality(thermalState: .fair, isLowPowerModeEnabled: true).reason, .lowPowerMode)
    }

    private func simulcastEncodings() -> [RTCRtpEncodingParameters] {
        return [4.0, 2.0, 1.0].map { scale in
            let encoding = RTCRtpEncodingParameters()
            encoding.scaleResolutionDownBy = NSNumber(value: scale)
            encoding.isActive = true
            return encoding
        }
    }

    func testLimitSimulcastEncodings() {
        let encodings = simulcastEncodings()

        XCTAssertTrue(NCPeerConnection.limitSendEncodings(encodings, withCodec: kRTCVideoCodecVp8Name, to: .medium))
        XCTAssertEqual(encodings.map(\.isActive), [true, true, false])
        // The layers themselves are not scaled, only switched off
        XCTAssertEqual(encodings.map { $0.scaleResolutionDownBy?.doubleValue }, [4, 2, 1])

        XCTAssertTrue(NCPeerConnection.limitSendEncodings(encodings, withCodec: kRTCVideoCodecVp8Name, to: .low))
        XCTAssertEqual(encodings.map(\.isActive), [true, false, false])

        XCTAssertTrue(NCPeerConnection.limitSendEncodings(encodings, withCodec: kRTCVideoCodecVp8Name, to: .high))
        XCTAssertEqual(encodings.map(\.isActive), [true, true, true])
    }

    func testLimitSimulcastEncodingsBeforeNegotiation() {
        let encodings = simulcastEncodings()

        XCTAssertFalse(NCPeerConnection.limitSendEncodings(encodings, withCodec: nil, to: .low))
        XCTAssertEqual(encodings.map(\.isActive), [true, true, true])
    }

    func testLimitSingleStream() {
        let encoding = RTCRtpEncodingParameters()
        encoding.isActive = true

        XCTAssertTrue(NCPeerConnection.limitSendEncodings([encoding], withCodec: nil, to: .medium))
        XCTAssertEqual(encoding.scaleResolutionDownBy?.doubleValue, 2)

        XCTAssertTrue(NCPeerConnection.limitSendEncodings([encoding], withCodec: nil, to: .high))
        XCTAssertEqual(encoding.scaleResolutionDownBy?.doubleValue, 1)
    }

    func testLimitSimulcastWithUnsupportedCodec() {
        // Only the highest layer is active without VP8, see disableSimulcastIfUnsupported
        let encodings = simulcastEncodings()
        encodings[0].isActive = false
        encodings[1].isActive = false

        XCTAssertTrue(NCPeerConnection.limitSendEncodings(encodings, withCodec: kRTCVideoCodecH264Name, to: .low))
        XCTAssertEqual(encodings.map(\.isActive), [false, false, true])
        XCTAssertEqual(encodings.map { $0.scaleResolutionDownBy?.doubleValue }, [4, 2, 4])
    }
}
