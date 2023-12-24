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

final class UIRoomTest: XCTestCase {

    override func setUpWithError() throws {
        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
    }

    func testCreateConversation() {
        let app = launchAndLogin()
        let newConversationName = "Test conversation"

        app.navigationBars["Nextcloud Talk"].buttons["Create a new conversation"].tap()
        XCTAssert(app.tables.cells.staticTexts["Create a new group conversation"].waitForExistence(timeout: TestConstants.timeoutShort))
        XCTAssert(app.tables.cells.staticTexts["Create a new public conversation"].waitForExistence(timeout: TestConstants.timeoutShort))
        XCTAssert(app.tables.cells.staticTexts["Show list of open conversations"].waitForExistence(timeout: TestConstants.timeoutShort))
        app.tables.cells.staticTexts["Create a new group conversation"].tap()
        app.navigationBars["RoomCreationTableView"].buttons["Next"].tap()
        app.typeText(newConversationName)
        XCTAssert(app.navigationBars["New group conversation"].buttons["Create"].waitForExistence(timeout: TestConstants.timeoutShort))
        app.navigationBars["New group conversation"].buttons["Create"].tap()

        let chatNavBar = app.navigationBars["NextcloudTalk.ChatView"]

        // Wait for navigationBar
        XCTAssert(chatNavBar.waitForExistence(timeout: TestConstants.timeoutLong))

        // Wait for titleView
        let chatTitleView = chatNavBar.textViews[newConversationName]
        XCTAssert(chatTitleView.waitForExistence(timeout: TestConstants.timeoutShort))

        // Wait until we joined the room and the call buttons get active
        let voiceCallButton = chatNavBar.buttons["Voice call"]
        XCTAssert(voiceCallButton.waitForExistence(timeout: TestConstants.timeoutShort))
        waitForEnabled(object: voiceCallButton)
        waitForHittable(object: voiceCallButton)

        // Open conversation settings
        chatTitleView.tap()

        // Check if if the name of the conversation is shown
        XCTAssert(app.textFields[newConversationName].waitForExistence(timeout: TestConstants.timeoutLong))

        // Go back to conversation list
        app.navigationBars["Conversation settings"].buttons["Back"].tap()
        chatNavBar.buttons["Back"].tap()

        // Check if the conversation appears in the conversation list
        XCTAssert(app.tables.cells.staticTexts[newConversationName].waitForExistence(timeout: TestConstants.timeoutLong))
    }

    func testChatViewControllerDeallocation() {
        let app = launchAndLogin()
        let newConversationName = "DeAllocTest"

        // Create a new test conversion
        app.navigationBars["Nextcloud Talk"].buttons["Create a new conversation"].tap()
        XCTAssert(app.tables.cells.staticTexts["Create a new group conversation"].waitForExistence(timeout: TestConstants.timeoutShort))
        XCTAssert(app.tables.cells.staticTexts["Create a new public conversation"].waitForExistence(timeout: TestConstants.timeoutShort))
        XCTAssert(app.tables.cells.staticTexts["Show list of open conversations"].waitForExistence(timeout: TestConstants.timeoutShort))
        app.tables.cells.staticTexts["Create a new group conversation"].tap()
        app.navigationBars["RoomCreationTableView"].buttons["Next"].tap()
        app.typeText(newConversationName)
        XCTAssert(app.navigationBars["New group conversation"].buttons["Create"].waitForExistence(timeout: TestConstants.timeoutShort))
        app.navigationBars["New group conversation"].buttons["Create"].tap()

        // Check if we have one chat view controller allocated
        XCTAssert(app.staticTexts["ChatVC: 1 / CallVC: 0"].waitForExistence(timeout: TestConstants.timeoutShort))

        // Send a test message
        let testMessage = "TestMessage"
        let toolbar = app.toolbars["Toolbar"]
        let textView = toolbar.textViews["Write message, @ to mention someone …"]
        XCTAssert(textView.waitForExistence(timeout: TestConstants.timeoutShort))
        textView.tap()
        app.typeText(testMessage)
        let sendMessageButton = toolbar.buttons["Send message"]
        sendMessageButton.tap()

        // Wait for temporary message to be replaced
        XCTAssert(app.images["MessageSent"].waitForExistence(timeout: TestConstants.timeoutShort))

        // Open context menu
        let tables = app.tables
        XCTAssert(tables.staticTexts[TestConstants.username].waitForExistence(timeout: TestConstants.timeoutShort))
        let message = tables.staticTexts[TestConstants.username]
        message.press(forDuration: 2.0)

        // Add a reaction to close the context menu
        let reactionExists = app.staticTexts["👍"].waitForExistence(timeout: TestConstants.timeoutShort)

        if reactionExists {
            app.staticTexts["👍"].tap()
        } else {
            // In case we are testing against a nextcloud version that does not support reactions (<= NC 23)
            // we simply tap the "Reply" button from the context menu
            XCTAssert(app.buttons["Reply"].waitForExistence(timeout: TestConstants.timeoutShort))
            app.buttons["Reply"].tap()
        }

        // Go back to the main view controller
        let chatNavBar = app.navigationBars["NextcloudTalk.ChatView"]
        chatNavBar.buttons["Back"].tap()

        // Check if all chat view controllers are deallocated
        XCTAssert(app.staticTexts["ChatVC: 0 / CallVC: 0"].waitForExistence(timeout: TestConstants.timeoutShort))
    }
}
