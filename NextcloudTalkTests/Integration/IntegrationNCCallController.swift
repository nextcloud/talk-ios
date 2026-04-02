//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
import Foundation
@testable import NextcloudTalk

final class IntegrationNCCallController: TestBase {

    func testCallJoinLeave() async throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = try await createUniqueRoom(prefix: "NCCallController", withAccount: activeAccount)
        let roomController = try await joinRoom(withToken: room.token, withAccount: activeAccount)

        let callControllerDelegate = NCCallControllerDelegateMock()
        let callController = NCCallController(delegate: callControllerDelegate, in: room, forAudioOnlyCall: false, withSessionId: roomController.userSessionId, andVoiceChatMode: true)

        callController.startCall()
        await fulfillment(of: [callControllerDelegate.expectationDidJoin], timeout: TestConstants.timeoutShort)

        let exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().getPeersForCall(inRoom: room.token, forAccount: activeAccount) { peers, error, statusCode in
            XCTAssertEqual(statusCode, 0)
            XCTAssertNil(error)

            // Check if we find our own session in the call
            XCTAssertTrue(peers!.contains(where: { ($0 as [String: Any])["sessionId"] as! String == roomController.userSessionId }))

            exp.fulfill()
        }

        await fulfillment(of: [exp])

        callController.leaveCall(forAll: true)
        await fulfillment(of: [callControllerDelegate.expectationDidEndCall], timeout: TestConstants.timeoutShort)
    }

}
