//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest

final class UICallTest: UITestCase {

    func testCallView() throws {
        let room = try createRoom(named: uniqueName("CallTest"))

        let app = launchAndLogin()
        openConversation(room, in: app)

        // Start a call
        let chatNavBar = app.navigationBars["NextcloudTalk.ChatView"]
        let callOptionsButton = chatNavBar.buttons["Call options"]
        waitForReady(object: callOptionsButton).tap()

        waitForReady(object: app.buttons["Video call"]).tap()

        let hangupCallButton = app.buttons["Hang up"]
        waitForReady(object: hangupCallButton)

        let moreMenuButton = app.buttons["moreMenuButton"]
        XCTAssert(moreMenuButton.waitForExistence(timeout: TestConstants.timeoutShort))

        // Try to enable background blur
        moreMenuButton.tap()
        let enableBlur = app.buttons["Enable blur"]
        XCTAssert(enableBlur.waitForExistence(timeout: TestConstants.timeoutShort))
        enableBlur.tap()

#if !targetEnvironment(simulator)
        // Try to disable background blur again
        moreMenuButton.tap()
        let disableBlur = app.buttons["Disable blur"]
        XCTAssert(disableBlur.waitForExistence(timeout: TestConstants.timeoutShort))
        disableBlur.tap()

        // Check if we are back at enable blur and tap it to close the menu
        moreMenuButton.tap()
        XCTAssert(enableBlur.waitForExistence(timeout: TestConstants.timeoutShort))
        enableBlur.tap()
#endif

        // Open chat
        let toggleChatButton = app.buttons["toggleChatButton"]
        XCTAssert(toggleChatButton.waitForExistence(timeout: TestConstants.timeoutShort))
        toggleChatButton.tap()

        // Close chat again
        let closeButton = app.buttons["closeChatButton"]
        XCTAssert(closeButton.waitForExistence(timeout: TestConstants.timeoutShort))
        closeButton.tap()

        // Hangup the call
        hangupCallButton.tap()

        // Go back to the main view controller
        XCTAssert(callOptionsButton.waitForExistence(timeout: TestConstants.timeoutShort))
        chatNavBar.buttons["Conversations"].tap()
    }
}
