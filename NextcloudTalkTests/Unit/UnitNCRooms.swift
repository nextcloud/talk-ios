//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Testing
@testable import NextcloudTalk

@Suite(.serialized)
final class UnitNCRooms: TestBaseRealm {

    private func createRoom(withDisplayName displayName: String, withType type: NCRoomType, isFavorite favorite: Bool, withLastActivity lastActivity: Int) -> NCRoom {
        let room = NCRoom()
        room.displayName = displayName
        room.type = type
        room.isFavorite = favorite
        room.lastActivity = lastActivity

        return room
    }

    @Test func `room sort`() throws {
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

        #expect(test1Begin == test1Expected)
    }

    @Test func `event visibility`() throws {
        let nonEventRoom = NCRoom()
        #expect(nonEventRoom.isVisible)

        let unfinishedEventRoom = NCRoom()
        unfinishedEventRoom.objectType = NCRoomObjectTypeEvent
        unfinishedEventRoom.objectId = "abcdefg" // "Unfinished" event rooms don't have a timestamp set, but a hash

        #expect(unfinishedEventRoom.isVisible)
        #expect(unfinishedEventRoom.eventTimestamps == nil)

        let timestampNow = Int(Date().timeIntervalSince1970)
        let eventRoom = NCRoom()
        eventRoom.objectType = NCRoomObjectTypeEvent

        // "Finished" event rooms store start/end-date in objectId as "<startTimestamp>#<endTimestamp>"
        var start = String(timestampNow + 15 * 3600)
        var end = String(timestampNow + 15 * 3600 + 60)
        eventRoom.objectId = "\(start)#\(end)"

        #expect(eventRoom.isVisible)
        #expect(eventRoom.eventTimestamps != nil)
        #expect(eventRoom.calendarEvent?.isFutureEvent ?? false)

        // Always show rooms of events in the past
        start = String(timestampNow - 5 * 3600)
        end = String(timestampNow - 5 * 3600 + 60)
        eventRoom.objectId = "\(start)#\(end)"
        #expect(eventRoom.isVisible)
        #expect(!(eventRoom.calendarEvent?.isFutureEvent ?? true))

        // Event rooms should only be shown 24h before start
        start = String(timestampNow + 17 * 3600)
        end = String(timestampNow + 17 * 3600 + 60)
        eventRoom.objectId = "\(start)#\(end)"
        #expect(!eventRoom.isVisible)
        #expect(eventRoom.calendarEvent?.isFutureEvent ?? false)
    }
}
