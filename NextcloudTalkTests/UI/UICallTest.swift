//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest

final class UICallTest: XCTestCase {

    override func setUpWithError() throws {
        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
    }

    func testCallView() {
        let app = launchAndLogin()
        let newConversationName = "CallTest"

        // Create a new test conversion
        self.createConversation(for: app, with: newConversationName)

        // Start a call
        let chatNavBar = app.navigationBars["NextcloudTalk.ChatView"]
        let callOptionsButton = chatNavBar.buttons["Call options"]
        waitForReady(object: callOptionsButton)
        callOptionsButton.tap()

        let videoCallButton = app.buttons["Video call"]
        XCTAssert(videoCallButton.waitForExistence(timeout: TestConstants.timeoutShort))
        videoCallButton.tap()

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

        // Check if we are back at enable blur
        XCTAssert(enableBlur.waitForExistence(timeout: TestConstants.timeoutShort))
#endif

        // Open chat
        let toggleChatButton = app.buttons["toggleChatButton"]
        XCTAssert(toggleChatButton.waitForExistence(timeout: TestConstants.timeoutShort))
        toggleChatButton.tap()

        // Close chat again
        let closeButton = app.buttons["closeInCallChatView"]
        XCTAssert(closeButton.waitForExistence(timeout: TestConstants.timeoutShort))
        closeButton.tap()

        // Hangup the call
        hangupCallButton.tap()

        // Go back to the main view controller
        XCTAssert(callOptionsButton.waitForExistence(timeout: TestConstants.timeoutShort))
        chatNavBar.buttons["Back"].tap()

        // Check if all call view controllers are deallocated
        XCTAssert(app.staticTexts["{}"].waitForExistence(timeout: TestConstants.timeoutShort))
    }
}
