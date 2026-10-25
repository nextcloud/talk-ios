//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitCallRecapTest: XCTestCase {

    private func recap(duration: TimeInterval, names: [String], reactions: Int = 0) -> CallRecap {
        return CallRecap(roomToken: "token", roomName: "Room", duration: duration, participantNames: names, reactionCount: reactions)
    }

    func testRecapIsOnlyShownForLongerCallsWithOthers() {
        XCTAssertFalse(recap(duration: 30, names: ["Alice"]).isWorthShowing)
        XCTAssertFalse(recap(duration: 600, names: []).isWorthShowing)
        XCTAssertTrue(recap(duration: CallRecap.minimumDuration, names: ["Alice"]).isWorthShowing)
    }

    func testRecapParticipantsDescription() {
        XCTAssertEqual(recap(duration: 600, names: []).participantsDescription, "")
        XCTAssertEqual(recap(duration: 600, names: ["Alice"]).participantsDescription, "Alice")
        XCTAssertEqual(recap(duration: 600, names: ["Alice", "Bob"]).participantsDescription, "Alice and Bob")
        XCTAssertEqual(recap(duration: 600, names: ["Alice", "Bob", "Carol"]).participantsDescription, "Alice, Bob and Carol")
        XCTAssertEqual(recap(duration: 600, names: ["Alice", "Bob", "Carol", "Dave", "Eve"]).participantsDescription, "Alice, Bob and 3 others")
    }

    func testRecapCollector() throws {
        let room = NCRoom()
        room.token = "abc"
        room.displayName = "Weekly sync"

        let collector = CallRecapCollector()

        // Nothing to summarize before the call started
        XCTAssertNil(collector.recap(for: room))

        let start = Date(timeIntervalSince1970: 1000)
        collector.callDidStart(at: start)
        // Joining again later (e.g. after reconnecting) keeps the first start
        collector.callDidStart(at: start.addingTimeInterval(100))

        collector.addParticipant(id: "users/alice", displayName: "Alice")
        collector.addParticipant(id: "guests/1", displayName: "Guest")
        collector.addParticipant(id: "users/alice", displayName: "Alice")
        // A guest changing the name keeps the position
        collector.addParticipant(id: "guests/1", displayName: "Bob")
        collector.addReaction()
        collector.addReaction()

        let recap = try XCTUnwrap(collector.recap(for: room, endDate: start.addingTimeInterval(42 * 60)))

        XCTAssertEqual(recap.roomToken, "abc")
        XCTAssertEqual(recap.roomName, "Weekly sync")
        XCTAssertEqual(recap.duration, 42 * 60)
        XCTAssertEqual(recap.participantNames, ["Alice", "Bob"])
        XCTAssertEqual(recap.reactionCount, 2)
        XCTAssertTrue(recap.isWorthShowing)
    }
}
