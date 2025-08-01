//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
import Foundation
@testable import NextcloudTalk

final class IntegrationChatTest: TestBase {

    func testSendMessage() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomName = "Integration Test Room 👍"
        let chatMessage = "Test Message 😀😆"

        var exp = expectation(description: "\(#function)\(#line)")
        var roomToken = ""

        // Create a room
        NCAPIController.sharedInstance().createRoom(forAccount: activeAccount, withInvite: nil, ofType: .public, andName: roomName) { room, error in
            XCTAssertNil(error)

            roomToken = room?.token ?? ""

            exp.fulfill()
        }
        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)

        // Send a message
        exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().sendChatMessage(chatMessage, toRoom: roomToken, threadTitle: "", replyTo: 0, referenceId: "", silently: false, for: activeAccount) { error in
            XCTAssertNil(error)

            exp.fulfill()
        }
        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)

        // Try to receive the sent message
        exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().receiveChatMessages(ofRoom: roomToken,
                                                             fromLastMessageId: 0,
                                                             inThread: 0,
                                                             history: true,
                                                             includeLastMessage: true,
                                                             timeout: false,
                                                             lastCommonReadMessage: 0,
                                                             setReadMarker: false,
                                                             markNotificationsAsRead: false,
                                                             for: activeAccount) { messages, _, _, error, errorCode in

            XCTAssertNil(error)
            XCTAssertEqual(errorCode, 0)

            for rawMessage in messages! {
                if let message = rawMessage as? NSDictionary {
                    // swiftlint:disable:next force_cast
                    if message.object(forKey: "message") as! String == chatMessage {
                        exp.fulfill()
                        return
                    }
                }
            }
        }
        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)
    }
}
