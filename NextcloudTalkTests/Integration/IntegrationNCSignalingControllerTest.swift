//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
import Foundation
@testable import NextcloudTalk

final class IntegrationNCSignalingControllerTest: TestBase {

    func testSendingSignalingMessage() async throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = try await createUniqueRoom(prefix: "NCSignalingController", withAccount: activeAccount)

        let exp = expectation(forNotification: .NCRoomsManagerDidJoinRoom, object: nil) { [roomToken = room.token!] notification -> Bool in
            XCTAssertNil(notification.userInfo?["error"])
            XCTAssertNil(notification.userInfo?["statusCode"])
            XCTAssertNil(notification.userInfo?["errorReason"])

            XCTAssertEqual(notification.userInfo?[stringForKey: "token"], roomToken)

            return true
        }

        NCRoomsManager.shared.joinRoom(room.token, forCall: false)
        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)

        let roomController = try XCTUnwrap(NCRoomsManager.shared.activeRooms[room.token])

        let message = NCControlMessage(from: roomController.userSessionId,
                                       to: roomController.userSessionId,
                                       sid: "",
                                       roomType: "video",
                                       payload: ["action": "testAction"])!

        // swiftlint:disable:next force_try
        let jsonData = try! JSONSerialization.data(withJSONObject: [message.messageDict()], options: [])
        let jsonDataString = String(data: jsonData, encoding: .utf8)!

        try await NCAPIController.sharedInstance().sendSignalingMessages(jsonDataString, toRoom: room.token, forAccount: activeAccount)

        let expPull = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().pullSignalingMessages(fromRoom: room.token, forAccount: activeAccount) { messages, error in
            XCTAssertNil(error)

            XCTAssertNotNil(messages!.contains(where: {
                guard let data = $0["data"] as? [String: AnyObject] else { return false }

                let payload = data["payload"] as! [String: AnyObject]
                return payload["action"] as! String == "testAction"
            }))

            expPull.fulfill()
        }

        await fulfillment(of: [expPull], timeout: TestConstants.timeoutShort)
    }

}
