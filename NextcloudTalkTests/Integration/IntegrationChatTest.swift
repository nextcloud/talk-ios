//
// Copyright (c) 2023 Marcel Müller <marcel-mueller@gmx.de>
//
// Author Marcel Müller <marcel-mueller@gmx.de>
//
// GNU GPL version 3 or any later version
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
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
        NCAPIController.sharedInstance().sendChatMessage(chatMessage, toRoom: roomToken, displayName: "", replyTo: 0, referenceId: "", silently: false, for: activeAccount) { error in
            XCTAssertNil(error)

            exp.fulfill()
        }
        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)

        // Try to receive the sent message
        exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().receiveChatMessages(ofRoom: roomToken,
                                                             fromLastMessageId: 0,
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
