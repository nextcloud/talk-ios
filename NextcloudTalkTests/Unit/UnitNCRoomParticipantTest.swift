//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitNCRoomParticipantTest: TestBaseRealm {

    func createRoomParticipant(withDisplayName displayName: String,
                               withActorType attendeeType: AttendeeType = .user,
                               isOffline offline: Bool = false,
                               isModerator moderator: Bool = false,
                               withInCall inCall: CallFlag = []) -> NCRoomParticipant {

        let participant = NCRoomParticipant(dictionary: [:])
        participant.displayName = displayName
        participant.actorType = attendeeType

        if moderator {
            participant.participantType = .moderator
        }

        if !offline {
            participant.sessionIds = ["abcdefg" + UUID().uuidString]
        }

        participant.inCall = inCall

        return participant
    }

    func testSorting() throws {
        let team9 = createRoomParticipant(withDisplayName: "9. Team", withActorType: .teams)
        let team8 = createRoomParticipant(withDisplayName: "8. Team", withActorType: .teams)
        let group7 = createRoomParticipant(withDisplayName: "7. Group", withActorType: .group)
        let group6 = createRoomParticipant(withDisplayName: "6. Group", withActorType: .group)
        let offline9 = createRoomParticipant(withDisplayName: "Offline 9", isOffline: true)
        let offline1 = createRoomParticipant(withDisplayName: "Offline 1", isOffline: true)
        let offline5 = createRoomParticipant(withDisplayName: "Offline 5", isOffline: true)
        let moderatorM = createRoomParticipant(withDisplayName: "Moderator M online", isModerator: true)
        let moderatorI = createRoomParticipant(withDisplayName: "Moderator I online", isModerator: true)
        let moderatorJ = createRoomParticipant(withDisplayName: "Moderator J offline", isOffline: true, isModerator: true)
        let regularZ = createRoomParticipant(withDisplayName: "Regular User Z")
        let regularA = createRoomParticipant(withDisplayName: "Regular User A")
        let regularN = createRoomParticipant(withDisplayName: "Regular User N")
        let inCall654 = createRoomParticipant(withDisplayName: "ZZ In call user 654", withInCall: .withPhone)
        let inCall123 = createRoomParticipant(withDisplayName: "ZZ In call user 123", withInCall: .withVideo)

        let participants = [
            team9, team8,
            group7, group6,
            offline9, offline1, offline5,
            moderatorM, moderatorI, moderatorJ,
            regularZ, regularA, regularN,
            inCall654, inCall123
        ]

        let sorted = participants.sortedParticipants()

        let expectedParticipants = [
            inCall123, inCall654,
            moderatorI, moderatorM,
            regularA, regularN, regularZ,
            moderatorJ,
            offline1, offline5, offline9,
            group6, group7,
            team8, team9
        ]

        XCTAssertEqual(sorted, expectedParticipants)
    }
}
