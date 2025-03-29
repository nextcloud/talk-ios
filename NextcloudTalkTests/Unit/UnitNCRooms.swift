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
        unfinishedEventRoom.objectType = NCRoomObjectTypeEvent
        unfinishedEventRoom.objectId = "abcdefg" // "Unfinished" event rooms don't have a timestamp set, but a hash

        XCTAssertTrue(unfinishedEventRoom.isVisible)
        XCTAssertNil(unfinishedEventRoom.eventTimestamps)

        let timestampNow = Int(Date().timeIntervalSince1970)
        let eventRoom = NCRoom()
        eventRoom.objectType = NCRoomObjectTypeEvent

        // "Finished" event rooms store start/end-date in objectId as "<startTimestamp>#<endTimestamp>"
        var start = String(timestampNow + 15 * 3600)
        var end = String(timestampNow + 15 * 3600 + 60)
        eventRoom.objectId = "\(start)#\(end)"

        XCTAssertTrue(eventRoom.isVisible)
        XCTAssertNotNil(eventRoom.eventTimestamps)
        XCTAssertTrue(eventRoom.calendarEvent?.isFutureEvent ?? false)

        // Always show rooms of events in the past
        start = String(timestampNow - 5 * 3600)
        end = String(timestampNow - 5 * 3600 + 60)
        eventRoom.objectId = "\(start)#\(end)"
        XCTAssertTrue(eventRoom.isVisible)
        XCTAssertFalse(eventRoom.calendarEvent?.isFutureEvent ?? true)

        // Event rooms should only be shown 24h before start
        start = String(timestampNow + 17 * 3600)
        end = String(timestampNow + 17 * 3600 + 60)
        eventRoom.objectId = "\(start)#\(end)"
        XCTAssertFalse(eventRoom.isVisible)
        XCTAssertTrue(eventRoom.calendarEvent?.isFutureEvent ?? false)
    }
}
