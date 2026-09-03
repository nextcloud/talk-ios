//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

// Covers `joinedRoomToken`, the state the chat relay is gated on: the signaling server only sends
// us the events of the room our session actually joined, so arming the relay on anything else
// (a server capability, `currentRoom`) stops the chat API polling while nothing is relayed to us.
final class UnitExternalSignalingControllerTest: TestBaseRealm {

    private var signalingController: NCExternalSignalingController!

    override func setUpWithError() throws {
        try super.setUpWithError()

        let account = NCDatabaseManager.sharedInstance().activeAccount()
        signalingController = NCExternalSignalingController(account: account, serverUrl: TestConstants.server, ticket: "fakeTicket")

        // Make the controller inert: without a websocket the delegate callbacks of the failing
        // connection attempt are ignored, so nothing reconnects underneath the assertions.
        signalingController.disconnect()
        drainMainQueue()
    }

    // MARK: - Helper

    private func drainMainQueue() {
        let exp = expectation(description: "\(#function)\(#line)")
        DispatchQueue.main.async { exp.fulfill() }
        waitForExpectations(timeout: TestConstants.timeoutShort, handler: nil)
    }

    private func helloMessage(withSessionId sessionId: String) -> [AnyHashable: Any] {
        return [
            "type": "hello",
            "id": "1",
            "hello": [
                "sessionid": sessionId,
                "resumeid": "fakeResumeId",
                "server": [
                    "version": "2.0.0",
                    "features": ["mcu", "chat-relay"]
                ]
            ]
        ]
    }

    private func roomMessage(withRoomToken roomToken: String) -> [AnyHashable: Any] {
        return ["type": "room", "room": ["roomid": roomToken]]
    }

    // MARK: - Tests

    func testJoinedRoomTokenIsOnlySetOnceTheRoomIsAcked() throws {
        XCTAssertNil(signalingController.joinedRoomToken)

        // Knowing the chat relay is supported does not mean we are in any room yet
        signalingController.helloResponseReceived(messageDict: helloMessage(withSessionId: "session-1"))
        XCTAssertTrue(signalingController.hasChatRelay)
        XCTAssertNil(signalingController.joinedRoomToken)

        signalingController.roomMessageReceived(messageDict: roomMessage(withRoomToken: "joinedToken"))
        XCTAssertEqual(signalingController.joinedRoomToken, "joinedToken")
    }

    func testJoinedRoomTokenIsPostedAsNotification() throws {
        expectation(forNotification: .extSignalingDidJoinRoom, object: signalingController) { notification in
            return notification.userInfo?["roomToken"] as? String == "joinedToken"
        }

        signalingController.roomMessageReceived(messageDict: roomMessage(withRoomToken: "joinedToken"))

        waitForExpectations(timeout: TestConstants.timeoutShort, handler: nil)
    }

    func testLeavingTheRoomClearsTheJoinedRoomToken() throws {
        signalingController.roomMessageReceived(messageDict: roomMessage(withRoomToken: "joinedToken"))
        XCTAssertEqual(signalingController.joinedRoomToken, "joinedToken")

        // The server acks leaving a room with an empty roomid
        signalingController.roomMessageReceived(messageDict: roomMessage(withRoomToken: ""))
        XCTAssertNil(signalingController.joinedRoomToken)
    }

    func testDisconnectingClearsTheJoinedRoomToken() throws {
        signalingController.roomMessageReceived(messageDict: roomMessage(withRoomToken: "joinedToken"))
        XCTAssertEqual(signalingController.joinedRoomToken, "joinedToken")

        // Unlike `currentRoom`, which survives a reconnect on purpose so we can re-join, the joined
        // room has to be cleared: the new connection is in no room until the server acks the re-join
        signalingController.resetWebSocket()
        XCTAssertNil(signalingController.joinedRoomToken)
        XCTAssertEqual(signalingController.currentRoom, "joinedToken")
    }

    func testNewSessionIsNotConsideredJoinedUntilItRejoined() throws {
        signalingController.helloResponseReceived(messageDict: helloMessage(withSessionId: "session-1"))
        signalingController.roomMessageReceived(messageDict: roomMessage(withRoomToken: "joinedToken"))
        XCTAssertEqual(signalingController.joinedRoomToken, "joinedToken")

        // We could not resume the session, so the server created a new one which is in no room yet
        signalingController.helloResponseReceived(messageDict: helloMessage(withSessionId: "session-2"))
        XCTAssertNil(signalingController.joinedRoomToken)

        // ... until the re-join is acked
        signalingController.roomMessageReceived(messageDict: roomMessage(withRoomToken: "joinedToken"))
        XCTAssertEqual(signalingController.joinedRoomToken, "joinedToken")

        drainMainQueue()
    }

    func testResumedSessionIsStillConsideredJoined() throws {
        signalingController.helloResponseReceived(messageDict: helloMessage(withSessionId: "session-1"))
        signalingController.roomMessageReceived(messageDict: roomMessage(withRoomToken: "joinedToken"))

        signalingController.resetWebSocket()
        XCTAssertNil(signalingController.joinedRoomToken)

        // The session was resumed (same session id), so the server kept us in the room and replays
        // the messages we missed while being disconnected. No re-join and no room ack follows here.
        signalingController.helloResponseReceived(messageDict: helloMessage(withSessionId: "session-1"))
        XCTAssertEqual(signalingController.joinedRoomToken, "joinedToken")

        drainMainQueue()
    }

    func testAlreadyJoinedErrorIsTreatedAsJoined() throws {
        signalingController.roomMessageReceived(messageDict: roomMessage(withRoomToken: "joinedToken"))
        signalingController.resetWebSocket()
        XCTAssertNil(signalingController.joinedRoomToken)

        // The server tells us we are still in the room. No room message follows in this case, so
        // without handling it here the relay would never be armed again for this room.
        let errorMessage: [AnyHashable: Any] = [
            "type": "error",
            "id": "2",
            "error": [
                "code": "already_joined",
                "details": ["room": ["roomid": "joinedToken"]]
            ]
        ]

        signalingController.errorResponseReceived(messageDict: errorMessage)
        XCTAssertEqual(signalingController.joinedRoomToken, "joinedToken")
    }
}
