//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitNCRooms: TestBaseRealm {

    private func createRoom(withDisplayName displayName: String, withType type: NCRoomType, isFavorite favorite: Bool, withLastActivity lastActivity: Int) -> NCRoom {
        let room = NCRoom()
        room.displayName = displayName
        room.type = type
        room.isFavorite = favorite
        room.lastActivity = lastActivity

        return room
    }

    func testRoomSort() throws {
        let favOneToOne = self.createRoom(withDisplayName: "FavRoom1 1-1", withType: .oneToOne, isFavorite: true, withLastActivity: 0)
        let favGroup = self.createRoom(withDisplayName: "FavRoom1 Group", withType: .group, isFavorite: true, withLastActivity: 0)
        let room1 = self.createRoom(withDisplayName: "Room1", withType: .group, isFavorite: false, withLastActivity: 1)
        let room2 = self.createRoom(withDisplayName: "Room2", withType: .group, isFavorite: false, withLastActivity: 2)
        let activity1 = self.createRoom(withDisplayName: "Activity1", withType: .oneToOne, isFavorite: false, withLastActivity: 123)
        let activity2 = self.createRoom(withDisplayName: "Activity2", withType: .oneToOne, isFavorite: false, withLastActivity: 456)

        let startArray = [
            activity2, activity1,
            favGroup, favOneToOne,
            room2, room1
        ]

        var test1Begin = startArray
        test1Begin.sortRooms(withGroupMode: .privateFirst, withSortOrder: .activity)

        let test1Expected = [
            favOneToOne, favGroup, activity2, activity1, room2, room1
        ]

        XCTAssertEqual(test1Begin, test1Expected)
    }

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

    private func createRoom(withAttributes attributes: NCRoomAttribute) -> NCRoom {
        let room = NCRoom()
        room.accountId = TestBaseRealm.fakeAccountId
        room.type = .group
        room.attributes = attributes
        return room
    }

    func testChannelAndAnnouncementDetection() throws {
        updateCapabilities { cap in
            cap.setValue([TalkCapability.announcementPreset.rawValue], forKey: "talkCapabilities")
            cap.callEnabled = true
        }

        // A regular group is neither a channel nor an announcement and supports calling
        let normalRoom = self.createRoom(withAttributes: [])
        XCTAssertFalse(normalRoom.isChannel)
        XCTAssertFalse(normalRoom.isAnnouncement)
        XCTAssertTrue(normalRoom.supportsCalling)

        // Channel: attributes & 8
        let channelRoom = self.createRoom(withAttributes: .channel)
        XCTAssertTrue(channelRoom.isChannel)
        XCTAssertFalse(channelRoom.isAnnouncement)
        XCTAssertFalse(channelRoom.supportsCalling)

        // Announcement: attributes set both the channel and announcement bits (8|16 = 24)
        let announcementRoom = self.createRoom(withAttributes: [.channel, .announcement])
        XCTAssertTrue(announcementRoom.isChannel)
        XCTAssertTrue(announcementRoom.isAnnouncement)
        XCTAssertFalse(announcementRoom.supportsCalling)
    }

    func testChannelDetectionRequiresCapability() throws {
        // Without the announcement-preset capability the attribute bits are ignored
        updateCapabilities { cap in
            cap.callEnabled = true
        }

        let channelRoom = self.createRoom(withAttributes: [.channel, .announcement])
        XCTAssertFalse(channelRoom.isChannel)
        XCTAssertFalse(channelRoom.isAnnouncement)

        // ...so the room behaves like a normal group and calling stays available
        XCTAssertTrue(channelRoom.supportsCalling)
    }
}
