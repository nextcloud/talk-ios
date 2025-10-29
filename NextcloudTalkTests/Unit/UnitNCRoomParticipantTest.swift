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

    func testInitWithDictionary() throws {
        let dataJson = """
            {
                    "roomToken": "tok3n",
                    "inCall": 7,
                    "lastPing": 1761683745,
                    "sessionIds": [
                        "session1",
                        "session2"
                    ],
                    "participantType": 1,
                    "attendeeId": 72,
                    "actorId": "admin",
                    "actorType": "users",
                    "displayName": "admin",
                    "permissions": 254,
                    "attendeePermissions": 0,
                    "attendeePin": "",
                    "phoneNumber": "",
                    "callId": "",
                    "status": "busy",
                    "statusIcon": "💬",
                    "statusMessage": "In a call",
                    "statusClearAt": null
            }
            """

        // swiftlint:disable:next force_cast
        let participantdict = try JSONSerialization.jsonObject(with: dataJson.data(using: .utf8)!) as! [String: Any]
        let participant = NCRoomParticipant(dictionary: participantdict)

        XCTAssertEqual(participant.attendeeId, 72)
        XCTAssertEqual(participant.actorId, "admin")
        XCTAssertEqual(participant.actorType, .user)
        XCTAssertEqual(participant.participantType, .owner)
        XCTAssertEqual(participant.displayName, "admin")
        XCTAssertEqual(participant.lastPing, 1761683745)
        XCTAssertEqual(participant.sessionIds?[0], "session1")
        XCTAssertEqual(participant.sessionIds?[1], "session2")
        XCTAssertEqual(participant.inCall, [.inCall, .withAudio, .withVideo])
        XCTAssertEqual(participant.status, "busy")
        XCTAssertEqual(participant.statusIcon, "💬")
        XCTAssertEqual(participant.statusMessage, "In a call")
        XCTAssertNil(participant.userId)
    }

}
