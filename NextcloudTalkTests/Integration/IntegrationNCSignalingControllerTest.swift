//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Testing
@testable import NextcloudTalk

@Suite(.serialized)
final class IntegrationNCSignalingControllerTest: TestBase {

    @Test func `sending signaling message`() async throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = try await createUniqueRoom(prefix: "NCSignalingController", withAccount: activeAccount)
        let roomController = try await joinRoom(withToken: room.token, withAccount: activeAccount)

        let message = NCControlMessage(from: roomController.userSessionId,
                                       to: roomController.userSessionId,
                                       sid: "",
                                       roomType: "video",
                                       payload: ["action": "testAction"])!

        let jsonData = try! JSONSerialization.data(withJSONObject: [message.messageDict()], options: [])
        let jsonDataString = String(data: jsonData, encoding: .utf8)!

        try await NCAPIController.sharedInstance().sendSignalingMessages(jsonDataString, toRoom: room.token, forAccount: activeAccount)

        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().pullSignalingMessages(fromRoom: room.token, forAccount: activeAccount) { messages, error in
                #expect(error == nil)

                #expect(messages!.contains(where: {
                    guard let data = $0["data"] as? [String: AnyObject] else { return false }

                    let payload = data["payload"] as! [String: AnyObject]
                    return payload["action"] as! String == "testAction"
                }))

                continuation.resume()
            }
        }
    }

}
