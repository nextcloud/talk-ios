//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Testing
@testable import NextcloudTalk

@Suite(.serialized)
final class IntegrationNCCallController: TestBase {

    @Test func `call join leave`() async throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = try await createUniqueRoom(prefix: "NCCallController", withAccount: activeAccount)
        let roomController = try await joinRoom(withToken: room.token, withAccount: activeAccount)

        let callControllerDelegate = NCCallControllerDelegateMock()
        let callController = NCCallController(delegate: callControllerDelegate, room: room, account: activeAccount, isAudioOnly: false, userSessionId: roomController.userSessionId, voiceChatMode: true)

        callController.startCall()
        let didJoin = await wait(timeout: TestConstants.timeoutShort) { callControllerDelegate.didJoinCall }
        #expect(didJoin)

        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().getPeersForCall(inRoom: room.token, forAccount: activeAccount) { peers, error, statusCode in
                #expect(statusCode == 0)
                #expect(error == nil)

                // Check if we find our own session in the call
                #expect(peers!.contains(where: { ($0 as [String: Any])["sessionId"] as! String == roomController.userSessionId }))

                continuation.resume()
            }
        }

        callController.leaveCall(forAll: true)
        let didEnd = await wait(timeout: TestConstants.timeoutShort) { callControllerDelegate.didEndCall }
        #expect(didEnd)
    }

}
