//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitCallLiveActivityManagerTest: XCTestCase {

    func testStatusForCallState() {
        XCTAssertEqual(CallLiveActivityManager.status(for: .joining), .connecting)
        XCTAssertEqual(CallLiveActivityManager.status(for: .switchingToAnotherRoom), .connecting)
        XCTAssertEqual(CallLiveActivityManager.status(for: .waitingParticipants), .waitingForParticipants)
        XCTAssertEqual(CallLiveActivityManager.status(for: .reconnecting), .reconnecting)
        XCTAssertEqual(CallLiveActivityManager.status(for: .inCall), .inCall)
    }

    func testCallStartDateIsSetWhenTheCallIsInProgress() {
        let now = Date(timeIntervalSince1970: 1_000)
        let connecting = CallActivityAttributes.ContentState(status: .connecting, isAudioMuted: false)

        let waiting = CallLiveActivityManager.contentState(connecting, changedBy: { $0.status = .waitingForParticipants }, now: now)
        XCTAssertNil(waiting.callStartDate)

        let inCall = CallLiveActivityManager.contentState(waiting, changedBy: { $0.status = .inCall }, now: now)
        XCTAssertEqual(inCall.callStartDate, now)
    }

    func testCallStartDateIsKept() {
        let serverStartDate = Date(timeIntervalSince1970: 500)
        let inCall = CallActivityAttributes.ContentState(status: .inCall, isAudioMuted: false, callStartDate: serverStartDate)

        let muted = CallLiveActivityManager.contentState(inCall, changedBy: { $0.isAudioMuted = true }, now: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(muted.callStartDate, serverStartDate)
        XCTAssertTrue(muted.isAudioMuted)
    }

    func testUnchangedContentStateIsEqual() {
        let inCall = CallActivityAttributes.ContentState(status: .inCall, isAudioMuted: true, participantCount: 3, callStartDate: Date(timeIntervalSince1970: 500))

        XCTAssertEqual(CallLiveActivityManager.contentState(inCall, changedBy: { $0.isAudioMuted = true }), inCall)
    }

    func testContentStateCoding() throws {
        let contentState = CallActivityAttributes.ContentState(status: .reconnecting, isAudioMuted: true, participantCount: 4, callStartDate: Date(timeIntervalSince1970: 500), avatarPath: "/tmp/avatar.png")

        let data = try JSONEncoder().encode(contentState)
        XCTAssertEqual(try JSONDecoder().decode(CallActivityAttributes.ContentState.self, from: data), contentState)
    }

    func testAvatarURL() throws {
        let avatarFolderURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("LiveActivities", isDirectory: true)

        let avatarURL = try XCTUnwrap(CallLiveActivityManager.avatarURL(forRoomToken: "abc123", in: avatarFolderURL))
        XCTAssertEqual(avatarURL.lastPathComponent, "abc123.png")
        XCTAssertEqual(avatarURL.deletingLastPathComponent().standardizedFileURL, avatarFolderURL.standardizedFileURL)

        let unsafeAvatarURL = try XCTUnwrap(CallLiveActivityManager.avatarURL(forRoomToken: "../a/b", in: avatarFolderURL))
        XCTAssertEqual(unsafeAvatarURL.deletingLastPathComponent().standardizedFileURL, avatarFolderURL.standardizedFileURL)
    }

    func testAvatarURLWithoutFolder() {
        XCTAssertNil(CallLiveActivityManager.avatarURL(forRoomToken: "abc123", in: nil))
    }
}
