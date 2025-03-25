//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitNCRooms: TestBaseRealm {

    func testEventVisibility() throws {
        let nonEventRoom = NCRoom()
        XCTAssertTrue(nonEventRoom.isVisible)

        let unfinishedEventRoom = NCRoom()
        unfinishedEventRoom.objectType = "event"
        unfinishedEventRoom.objectId = "abcdefg" // unfinished event rooms don't have a timestamp set, but a hash

        XCTAssertTrue(unfinishedEventRoom.isVisible)
        XCTAssertNil(unfinishedEventRoom.eventStartTimestamp)

        let timestampNow = Int(Date().timeIntervalSince1970)
        let eventRoom = NCRoom()
        eventRoom.objectType = "event"
        eventRoom.objectId = String(timestampNow + 15 * 3600)

        XCTAssertTrue(eventRoom.isVisible)
        XCTAssertNotNil(eventRoom.eventStartTimestamp)

        // Always show rooms of events in the past
        eventRoom.objectId = String(timestampNow - 5 * 3600)
        XCTAssertTrue(eventRoom.isVisible)

        // Event rooms should only be shown 24h before start
        eventRoom.objectId = String(timestampNow + 17 * 3600)
        XCTAssertFalse(eventRoom.isVisible)
    }
}
