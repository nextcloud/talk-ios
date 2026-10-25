//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitCallPreflightTest: XCTestCase {

    func testMicrophoneLevelNormalization() {
        XCTAssertEqual(CallPreflightModel.normalizedLevel(fromDecibels: -160), 0)
        XCTAssertEqual(CallPreflightModel.normalizedLevel(fromDecibels: -50), 0)
        XCTAssertEqual(CallPreflightModel.normalizedLevel(fromDecibels: -25), 0.5, accuracy: 0.001)
        XCTAssertEqual(CallPreflightModel.normalizedLevel(fromDecibels: 0), 1)
        XCTAssertEqual(CallPreflightModel.normalizedLevel(fromDecibels: 6), 1)
        XCTAssertEqual(CallPreflightModel.normalizedLevel(fromDecibels: -.infinity), 0)
        XCTAssertEqual(CallPreflightModel.normalizedLevel(fromDecibels: .nan), 0)
    }

    func testPreflightResultIsTakenOnlyOnceAndOnlyForTheSameConversation() {
        let result = CallPreflightResult(cameraEnabled: false, microphoneEnabled: true)

        CallPreflightPreferences.store(result, for: "token1")

        XCTAssertNil(CallPreflightPreferences.take(for: "token2"))
        XCTAssertEqual(CallPreflightPreferences.take(for: "token1"), result)
        XCTAssertNil(CallPreflightPreferences.take(for: "token1"))
    }
}
