//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest

final class UIRoomTest: XCTestCase {

    override func setUpWithError() throws {
        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
    }

    func testCreateAndDeleteConversation() {
        let app = launchAndLogin()
        let newConversationName = "Test conversation" + UUID().uuidString

        self.createConversation(for: app, with: newConversationName)

        let chatNavBar = app.navigationBars["NextcloudTalk.ChatView"]

        // Wait for navigationBar
        XCTAssert(chatNavBar.waitForExistence(timeout: TestConstants.timeoutLong))

        // Wait for titleView
        let chatTitleView = chatNavBar.textViews[newConversationName]
        XCTAssert(chatTitleView.waitForExistence(timeout: TestConstants.timeoutShort))

        // Wait until we joined the room and the call buttons get active
        let callOptionsButton = chatNavBar.buttons["Call options"]
        waitForReady(object: callOptionsButton)

        // Open conversation settings
        chatTitleView.tap()

        // Check if if the name of the conversation is shown
        let conversationTextField = app.textFields[newConversationName]
        XCTAssert(conversationTextField.waitForExistence(timeout: TestConstants.timeoutLong))

        // Go back to conversation list
        app.navigationBars["Conversation settings"].buttons["Back"].tap()
        chatNavBar.buttons["Back"].tap()

        // Check if the conversation appears in the conversation list
        let conversationStaticText = app.tables.cells.staticTexts[newConversationName]
        XCTAssert(conversationStaticText.waitForExistence(timeout: TestConstants.timeoutLong))

        // Try to delete the room
        conversationStaticText.press(forDuration: 2.0)
        let deleteConversation = app.buttons["Delete conversation"]
        XCTAssert(conversationStaticText.waitForExistence(timeout: TestConstants.timeoutShort))

        deleteConversation.tap()
        let alert = app.alerts.element.staticTexts["Delete conversation"]
        XCTAssert(alert.waitForExistence(timeout: TestConstants.timeoutShort))

        app.buttons["Delete"].tap()

        XCTAssert(conversationTextField.waitForNonExistence(timeout: TestConstants.timeoutShort))
    }

    func testDeallocation() {
        let app = launchAndLogin()
        let newConversationName = "DeAllocTest"

        // Create a new test conversion
        self.createConversation(for: app, with: newConversationName)

        // Check if we have one chat view controller allocated
        let debugLabel = app.staticTexts.labelContains("ChatViewController\":1").firstMatch
        XCTAssert(debugLabel.waitForExistence(timeout: TestConstants.timeoutShort))

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
        let messageSentImage = app.images["MessageSent"]
        XCTAssert(messageSentImage.waitForExistence(timeout: TestConstants.timeoutShort))

        // Open context menu
        messageSentImage.press(forDuration: 2.0)

        // Add a reaction to close the context menu
        // In case we are testing against a nextcloud version that does not support reactions (<= NC 23)
        // we simply tap the "Reply" button from the context menu
        let foundElement = waitForEitherElementToExist(app.staticTexts["👍"], app.buttons["Reply"], TestConstants.timeoutShort)
        waitForReady(object: foundElement).tap()

        // Start a call and hangup afterwards
        let chatNavBar = app.navigationBars["NextcloudTalk.ChatView"]
        let callOptionsButton = chatNavBar.buttons["Call options"]
        waitForReady(object: callOptionsButton).tap()

        waitForReady(object: app.buttons["Voice only call"]).tap()
        waitForReady(object: app.buttons["Hang up"]).tap()

        /*
            // Disabled for now, as there are too many timeouts on CI.

            // Share an image and open the media preview
            waitForReady(object: app.buttons["shareButton"]).tap()
            waitForReady(object: app.buttons["Photo Library"]).tap()

            // All photos in simulator start with "Photo", use the first one
            waitForReady(object: app.images.labelContains("Photo").firstMatch).tap()
            app.buttons["Add"].tap()

            // On old versions, we don't have an inputbar on the sharing dialog, therefore also check for the send button
            let foundSendButton = waitForEitherElementToExist(sendMessageButton, app.buttons["Send"], TestConstants.timeoutShort)
            waitForReady(object: foundSendButton).tap()

            // Open the preview and close it again
            waitForReady(object: app.images["filePreviewImageView"], timeout: TestConstants.timeoutLong + 60).tap()
            waitForReady(object: app.buttons["Close"]).tap()
        */

        // Go back to the main view controller
        XCTAssert(callOptionsButton.waitForExistence(timeout: TestConstants.timeoutShort))
        chatNavBar.buttons["Back"].tap()

        // Check if all controllers are deallocated
        XCTAssert(app.staticTexts["{}"].waitForExistence(timeout: TestConstants.timeoutShort))
    }

    func testChatViewControllerMentions() {
        let app = launchAndLogin()
        let newConversationName = "MentionTest 🇨🇨"

        // Create a new test conversion
        self.createConversation(for: app, with: newConversationName)

        // Select a mention
        let toolbar = app.toolbars["Toolbar"]
        let textView = toolbar.textViews["Write message, @ to mention someone …"]
        XCTAssert(textView.waitForExistence(timeout: TestConstants.timeoutShort))
        textView.tap()
        textView.typeText("@")
        textView.typeText("M")
        textView.typeText("e")

        let autoCompleteCell = app.tables.cells["AutoCompletionCellIdentifier"].staticTexts.labelContains(newConversationName).firstMatch
        XCTAssert(autoCompleteCell.waitForExistence(timeout: TestConstants.timeoutShort))

        autoCompleteCell.tap()

        // Check if the mention was correctly inserted in the textView
        XCTAssertEqual(textView.value as? String ?? "", "@\(newConversationName) ")

        // Remove the mention again
        textView.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))

        // Check if the input field is now empty
        XCTAssertEqual(textView.value as? String ?? "", "")

        // Try to send a mention and check if it's rendered
        textView.tap()
        textView.typeText("@")
        textView.typeText("M")
        textView.typeText("e")

        XCTAssert(autoCompleteCell.waitForExistence(timeout: TestConstants.timeoutShort))

        autoCompleteCell.tap()

        // Check if the mention was correctly inserted in the textView
        XCTAssertEqual(textView.value as? String ?? "", "@\(newConversationName) ")

        let sendMessageButton = toolbar.buttons["Send message"]
        sendMessageButton.tap()

        // Wait for temporary message to be replaced
        XCTAssert(app.images["MessageSent"].waitForExistence(timeout: TestConstants.timeoutShort))

        let tables = app.tables
        var messageTextView = tables.textViews["@\(newConversationName)"]
        XCTAssert(messageTextView.waitForExistence(timeout: TestConstants.timeoutShort))

        // Open context menu
        messageTextView.descendants(matching: .any)["@\(newConversationName)"].press(forDuration: 2.0)

        // Check if 'Edit' exists
        let editButton = app.buttons["Edit"]
        let editExists = editButton.waitForExistence(timeout: TestConstants.timeoutShort)

        // Edit might not be supported by the server. Check for reply button to ensure context menu was correctly displayed
        if !editExists {
            if !app.buttons["Reply"].exists {
                XCTFail("Neither edit, nor reply button exist")
            }

            return
        }

        editButton.tap()

        // Wait for the original text to be shown in the textView
        let textViewValue = toolbar.descendants(matching: .any).valueContains("@\(newConversationName)").firstMatch
        XCTAssert(textViewValue.waitForExistence(timeout: TestConstants.timeoutShort))

        textView.typeText(" Edited")

        // TODO: Should change the lib to have a proper identifier here
        // Save the edit
        toolbar.buttons["selected"].tap()

        // Check if the edit is correct
        messageTextView = tables.textViews["@\(newConversationName) Edited"]
        XCTAssert(messageTextView.waitForExistence(timeout: TestConstants.timeoutShort))
    }

    func testLobbyView() {
        let app = launchAndLogin()

        let lobbyCell = app.tables.cells.staticTexts["LobbyTest"]
        XCTAssert(lobbyCell.waitForExistence(timeout: TestConstants.timeoutShort))

        lobbyCell.tap()

        // Check that the lobby view is displayed
        let backgroundView = app.descendants(matching: .any)["Chat PlacerholderView"]
        let lobbyTextView = backgroundView.textViews["You are currently waiting in the lobby"]

        XCTAssert(lobbyTextView.waitForExistence(timeout: TestConstants.timeoutShort))

        // Check that the table has no rows
        let tables = app.tables.firstMatch
        XCTAssert(tables.waitForExistence(timeout: TestConstants.timeoutShort))

        XCTAssertEqual(tables.tableRows.count, 0)

        // Check that there's no activity indicator
        XCTAssertEqual(app.activityIndicators.count, 0)

        let shareButton = app.buttons["Share a file from your Nextcloud"]
        XCTAssert(!shareButton.exists)

        // Check that there's no inputbar
        let toolbar = app.toolbars["Toolbar"]
        let textView = toolbar.textViews["Write message, @ to mention someone …"]
        XCTAssert(!textView.exists)
    }
}
