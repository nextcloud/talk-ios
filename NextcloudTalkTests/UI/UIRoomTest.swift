//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UniformTypeIdentifiers
import XCTest

final class UIRoomTest: UITestCase {

    func testCreateAndDeleteConversation() throws {
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
        chatNavBar.buttons["Conversations"].tap()

        // Check if the conversation appears in the conversation list
        let conversationStaticText = app.tables.cells.staticTexts[newConversationName]
        XCTAssert(conversationStaticText.waitForExistence(timeout: TestConstants.timeoutLong))

        // Try to delete the room
        openContextMenu(of: conversationStaticText)
        let deleteConversation = app.buttons["Delete conversation"]
        XCTAssert(deleteConversation.waitForExistence(timeout: TestConstants.timeoutShort))

        deleteConversation.tap()
        let alert = app.alerts.element.staticTexts["Delete conversation"]
        XCTAssert(alert.waitForExistence(timeout: TestConstants.timeoutShort))

        app.buttons["Delete"].tap()

        // The cell is removed right away, before the server deleted the conversation
        XCTAssert(conversationStaticText.waitForNonExistence(timeout: TestConstants.timeoutShort))

        let deletedOnServer = try waitForServer {
            try !UITestServer.roomNames(for: .admin).contains(newConversationName)
        }
        XCTAssert(deletedOnServer, "Server still lists the deleted conversation")

        // Only a list loaded after deleting can contain a conversation created after deleting,
        // so once it is shown, a reload has happened that must not bring the deleted conversation back
        let markerRoom = try createRoom(named: uniqueName("RefreshMarker"))
        app.tables.firstMatch.pullToRefresh()
        XCTAssert(app.tables.cells.staticTexts[markerRoom.name].waitForExistence(timeout: TestConstants.timeoutShort))

        XCTAssertFalse(conversationStaticText.exists, "Deleted conversation is still in the conversation list")
    }

    func testJoinAndLeaveConversation() throws {
        // Created by another user, so we are not a participant yet
        let room = try createRoom(named: uniqueName("OpenConversationTest"), as: .alice)
        try UITestServer.setListable(.registeredUsers, for: room)

        let app = launchAndLogin()
        let openConversationName = room.name

        waitForReady(object: app.buttons["Create or join a conversation"]).tap()
        waitForReady(object: app.tables.cells.staticTexts["Join open conversations"]).tap()
        waitForReady(object: app.tables.cells.staticTexts[openConversationName]).tap()

        let chatNavBar = app.navigationBars["NextcloudTalk.ChatView"]

        // Wait for navigationBar
        XCTAssert(chatNavBar.waitForExistence(timeout: TestConstants.timeoutLong))

        // Wait for titleView
        let chatTitleView = chatNavBar.textViews[openConversationName]
        XCTAssert(chatTitleView.waitForExistence(timeout: TestConstants.timeoutShort))

        // Wait until we joined the room and the call buttons get active
        let callOptionsButton = chatNavBar.buttons["Call options"]
        waitForReady(object: callOptionsButton)

        // Open conversation settings
        chatTitleView.tap()

        // The list is lazy, so the indicator is only rendered when the leave button below it is on screen
        let leaveButton = app.buttons["Leave conversation"]
        app.scrollTo(leaveButton)
        let participantsLoadingIndicator = app.descendants(matching: .any)["ParticipantsLoadingIndicator"]
        XCTAssert(participantsLoadingIndicator.waitForNonExistence(timeout: TestConstants.timeoutShort))

        // Loaded participants push the button almost off screen, where it still counts as hittable
        app.swipeUp()
        app.scrollTo(leaveButton)

        // Leave open conversation
        leaveButton.tap()
        waitForReady(object: app.alerts.buttons["Leave"]).tap()
        waitForReady(object: app.buttons["Create or join a conversation"])

        // Closing the settings shows the chat again, which once joined the open conversation right away and made us a
        // participant again (fixed in 27773173f). Depending on the list reload that is only visible later, so we wait for
        // a list loaded after leaving: it is the first one that can contain a conversation created after leaving
        let markerRoom = try createRoom(named: uniqueName("RefreshMarker"))
        app.tables.firstMatch.pullToRefresh()
        XCTAssert(app.tables.cells.staticTexts[markerRoom.name].waitForExistence(timeout: TestConstants.timeoutShort))

        XCTAssertFalse(app.tables.cells.staticTexts[openConversationName].exists, "Left conversation is still in the conversation list")
        XCTAssertFalse(try UITestServer.roomNames(for: .admin).contains(openConversationName), "Server still lists us as participant of the left conversation")
    }

    func testMessageSearch() throws {
        let supportsReactions = try UITestServer.hasTalkFeature("reactions")
        let supportsMessageContext = try UITestServer.hasTalkFeature("chat-get-context")
        let room = try createRoom(named: uniqueName("MessageSearchTest"))

        let app = launchAndLogin()
        openConversation(room, in: app)

        // The tracker has to count the open chat, otherwise the deallocation check after every test would pass trivially
        let debugLabel = app.staticTexts.labelContains("ChatViewController\":1").firstMatch
        XCTAssert(debugLabel.waitForExistence(timeout: TestConstants.timeoutShort))

        // Send a test message. The message needs to be unique, because conversations of previous
        // test runs can still be on the server (failed cleanup) and would also be found when searching for it later.
        let testMessage = "TestMessage - Search \(UUID().uuidString.prefix(8))"
        sendMessage(testMessage, in: app)

        // Wait for temporary message to be replaced
        let messageSentCell = app.cells["CellMessageSent"]
        XCTAssert(messageSentCell.waitForExistence(timeout: TestConstants.timeoutShort))

        // Close the context menu again with a reaction, servers without reactions (< Talk 14) only offer a reply
        openContextMenu(of: messageSentCell)

        if supportsReactions {
            waitForReady(object: contextMenuReaction("👍", in: app)).tap()
        } else {
            waitForReady(object: app.buttons["Reply"]).tap()
        }

        // Go back to the main view controller
        let chatNavBar = app.navigationBars["NextcloudTalk.ChatView"]
        waitForReady(object: chatNavBar.buttons["Conversations"]).tap()

        // Search for the message we just wrote and open its context
        waitForReady(object: app.searchFields.firstMatch).tap()
        app.typeText(testMessage)

        // Only tap on a result from the "Messages" section that really shows our message. The
        // conversation list stays in the hierarchy while searching, so matching by label alone can
        // resolve to a conversation cell behind the search results, which never becomes hittable.
        let messageResultCell = app.cells.matching(identifier: "MessageSearchResultCell").containingLabel(testMessage).firstMatch
        waitForReady(object: messageResultCell, timeout: TestConstants.timeoutLong).tap()

        // On servers without the "chat-get-context" capability (< Talk 17) we are not able to show the
        // context of the message and open the conversation of the message instead
        let contextNavBar = app.navigationBars["NextcloudTalk.ContextChatView"]

        if supportsMessageContext {
            // Check that the context of our message is shown
            XCTAssert(contextNavBar.waitForExistence(timeout: TestConstants.timeoutShort))
            XCTAssert(app.tables.textViews.labelContains(testMessage).firstMatch.waitForExistence(timeout: TestConstants.timeoutShort))

            // Close the ContextChatViewController again
            waitForReady(object: contextNavBar.buttons["Close"]).tap()
        } else {
            // Go back to the conversation list again
            XCTAssert(chatNavBar.waitForExistence(timeout: TestConstants.timeoutShort))
            waitForReady(object: chatNavBar.buttons["Conversations"]).tap()
        }

        // Close the SearchController
        app.buttons["close"].tap()
    }

    func testShareImage() throws {
        let supportsCaptions = try UITestServer.hasTalkFeature("media-caption")
        let room = try createRoom(named: uniqueName("ShareTest"))

        let app = launchAndLogin()
        openConversation(room, in: app)

        // Pasting avoids the system photo picker
        UIPasteboard.general.setData(generatedImagePNG(), forPasteboardType: UTType.png.identifier)

        let textView = messageTextView(in: app)
        XCTAssert(textView.waitForExistence(timeout: TestConstants.timeoutShort))
        textView.tap()

        // Typing cmd+v is unreliable, it races with the keyboard focus
        textView.press(forDuration: 1.0)
        waitForReady(object: app.menuItems["Paste"]).tap()

        let shareConfirmation = app.otherElements["ShareConfirmationView"]
        XCTAssert(shareConfirmation.waitForExistence(timeout: TestConstants.timeoutShort))

        // Without captions the send button is in the navigation bar
        let sendButton = supportsCaptions ? shareConfirmation.otherElements["SLKTextInputbar"].buttons["Send message"] : app.navigationBars.buttons["Send"]
        waitForReady(object: sendButton).tap()

        // Skip the pending upload, which uses the same preview
        let sentFilePreview = app.cells["CellMessageSent"].images["filePreviewImageView"]
        waitForReady(object: sentFilePreview, timeout: TestConstants.timeoutLong).tap()

        // Close the media viewer
        waitForReady(object: app.buttons["Close"]).tap()
    }

    // Small, so upload and server preview stay fast
    private func generatedImagePNG() -> Data {
        let size = CGSize(width: 64, height: 64)

        return UIGraphicsImageRenderer(size: size).pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testMessageQuoting() throws {
        let room = try createRoom(named: uniqueName("QuoteTest"))

        let app = launchAndLogin()
        openConversation(room, in: app)

        // Send a test message
        sendMessage("TestMessage", in: app)

        // Wait for temporary message to be replaced
        let messageSentCell = app.cells["CellMessageSent"]
        XCTAssert(messageSentCell.waitForExistence(timeout: TestConstants.timeoutShort))

        // Start a reply
        openContextMenu(of: messageSentCell)
        waitForReady(object: app.buttons["Reply"]).tap()

        // Send the reply and check if the temporary message is replaced
        sendMessage("ReplyMessage", in: app)

        // Two messages should now be in the sent state
        waitForCount(query: app.cells.matching(identifier: "CellMessageSent"), count: 2, timeout: TestConstants.timeoutShort)
    }

    func testChatViewControllerMentions() throws {
        let canEditMessages = try UITestServer.hasTalkFeature("edit-messages")

        // The conversation itself is offered as mention, so its name is what we type and check for
        let room = try createRoom(named: uniqueName("MentionTest 🇨🇨"))
        let newConversationName = room.name

        let app = launchAndLogin()
        openConversation(room, in: app)

        // Select a mention
        let toolbar = messageInputBar(in: app)
        let textView = messageTextView(in: app)
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
        XCTAssert(app.cells["CellMessageSent"].waitForExistence(timeout: TestConstants.timeoutShort))

        let tables = app.tables
        var messageTextView = tables.textViews["@\(newConversationName)"]
        XCTAssert(messageTextView.waitForExistence(timeout: TestConstants.timeoutShort))

        openContextMenu(of: messageTextView.descendants(matching: .any)["@\(newConversationName)"])

        // Editing the mention is only possible with "edit-messages" (Talk 18+). Otherwise the reply closes the context menu again
        guard canEditMessages else {
            waitForReady(object: app.buttons["Reply"]).tap()
            return
        }

        waitForReady(object: app.buttons["Edit"]).tap()

        // Wait for the original text to be shown in the textView
        let textViewValue = toolbar.descendants(matching: .any).valueContains("@\(newConversationName)").firstMatch
        XCTAssert(textViewValue.waitForExistence(timeout: TestConstants.timeoutShort))

        textView.typeText(" Edited")

        // Save the edit
        toolbar.buttons["Save changes"].tap()

        // Check if the edit is correct
        messageTextView = tables.textViews["@\(newConversationName) Edited"]
        XCTAssert(messageTextView.waitForExistence(timeout: TestConstants.timeoutShort))
    }

    func testLobbyView() throws {
        // Created by another user, so we are a normal participant waiting in the lobby
        let room = try createRoom(named: uniqueName("LobbyTest"), as: .alice)
        try UITestServer.enableLobby(in: room)
        try UITestServer.addParticipant(.admin, to: room)

        let app = launchAndLogin()
        openConversation(room, in: app)

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

        assertNoMessageInput(in: app)
    }

    func testReactOnlyPermission() throws {
        try XCTSkipUnless(UITestServer.hasTalkFeature("react-permission"), "Requires the react-permission capability (Talk 24+)")

        // Created by another user, we only get the default permissions, which allow to react but not to chat
        let message = "React to this message!"
        let room = try createRoom(named: uniqueName("ReactOnlyTest"), as: .alice)
        try UITestServer.setDefaultPermissions(UITestServer.defaultPermissionsReactOnly, for: room)
        try UITestServer.addParticipant(.admin, to: room)
        try UITestServer.sendMessage(message, to: room, as: .alice)

        let app = launchAndLogin()
        openConversation(room, in: app)

        // Find the message from alice that we should react to
        let messageText = app.tables.textViews[message].firstMatch
        XCTAssert(messageText.waitForExistence(timeout: TestConstants.timeoutShort))

        openContextMenu(of: messageText)

        let thumbsUpReaction = contextMenuReaction("👍", in: app)
        XCTAssert(thumbsUpReaction.waitForExistence(timeout: TestConstants.timeoutShort))
        thumbsUpReaction.tap()

        // Verify the reaction was added - the reaction label shows "emoji count" format
        let reactionLabel = app.staticTexts["👍 1"]
        XCTAssert(reactionLabel.waitForExistence(timeout: TestConstants.timeoutShort),
                 "Reaction should be visible after adding it")

        // Verify that we cannot send messages (no chat permission)
        assertNoMessageInput(in: app)
    }
}
