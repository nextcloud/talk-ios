//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitVoicePlaybackSpeedTest: XCTestCase {

    func testPlaybackSpeedCycle() {
        XCTAssertEqual(VoiceMessagePlaybackSpeed.next(after: 1), 1.5)
        XCTAssertEqual(VoiceMessagePlaybackSpeed.next(after: 1.5), 2)
        XCTAssertEqual(VoiceMessagePlaybackSpeed.next(after: 2), 1)
        // Unknown speeds start over
        XCTAssertEqual(VoiceMessagePlaybackSpeed.next(after: 3), 1)
    }

    func testPlaybackSpeedLabel() {
        XCTAssertEqual(VoiceMessagePlaybackSpeed.label(for: 1, locale: Locale(identifier: "en_US")), "1×")
        XCTAssertEqual(VoiceMessagePlaybackSpeed.label(for: 1.5, locale: Locale(identifier: "en_US")), "1.5×")
        XCTAssertEqual(VoiceMessagePlaybackSpeed.label(for: 1.5, locale: Locale(identifier: "de_DE")), "1,5×")
        XCTAssertEqual(VoiceMessagePlaybackSpeed.label(for: 2, locale: Locale(identifier: "de_DE")), "2×")
    }
}
