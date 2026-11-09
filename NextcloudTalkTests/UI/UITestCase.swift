//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest

class UITestCase: XCTestCase {

    private var createdRooms: [TestRoom] = []

    override func setUpWithError() throws {
        try super.setUpWithError()

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // A failing check must not stop the tear down, the rooms still need to be deleted
        continueAfterFailure = true

        // After a failure or skip the app is in an unknown state, the original failure is what matters
        if let testRun, testRun.hasSucceeded, !testRun.hasBeenSkipped {
            checkDeallocation()
        }

        // Deleted only now, deleting a room while its chat is still open interferes with the check above
        for room in createdRooms.reversed() {
            try? UITestServer.deleteRoom(room)
        }

        createdRooms = []

        try super.tearDownWithError()
    }

    // The room is deleted again when the test finishes, whatever the outcome
    func createRoom(named name: String, type: UITestServer.RoomType = .group, as owner: TestUser = .admin) throws -> TestRoom {
        let room = try UITestServer.createRoom(named: name, type: type, as: owner)
        createdRooms.append(room)

        return room
    }

    // MARK: - Chat

    func messageInputBar(in app: XCUIApplication) -> XCUIElement {
        return app.otherElements["SLKTextInputbar"]
    }

    func messageTextView(in app: XCUIApplication) -> XCUIElement {
        return messageInputBar(in: app).textViews["Write message, @ to mention someone …"]
    }

    // Does not wait for the message to be sent, what to check for (count, content) depends on the test
    func sendMessage(_ message: String, in app: XCUIApplication) {
        let textView = messageTextView(in: app)
        XCTAssert(textView.waitForExistence(timeout: TestConstants.timeoutShort))
        textView.tap()
        app.typeText(message)
        messageInputBar(in: app).buttons["Send message"].tap()
    }

    func assertNoMessageInput(in app: XCUIApplication) {
        XCTAssertFalse(messageTextView(in: app).exists, "Message input should not be available")
    }

    func openContextMenu(of element: XCUIElement) {
        element.press(forDuration: 2.0)
    }

    // The emoji of the reaction shortcuts is drawn into an image, so match on the label instead of an element type
    func contextMenuReaction(_ emoji: String, in app: XCUIApplication) -> XCUIElement {
        return app.descendants(matching: .any).labelContains(emoji).firstMatch
    }

    // MARK: - Deallocation

    // Every test has to release all tracked objects (controllers, calls, chats) once we are back at the conversation list
    private func checkDeallocation() {
        let app = XCUIApplication()
        // A crash after the last interaction of a test is only noticed when the app is queried again
        guard app.state == .runningForeground else {
            XCTFail("App is not running in the foreground anymore, it might have crashed")
            return
        }

        let chatNavBar = app.navigationBars["NextcloudTalk.ChatView"]
        if chatNavBar.exists {
            chatNavBar.buttons["Conversations"].tap()
        }

        XCTAssert(app.staticTexts["{}"].waitForExistence(timeout: TestConstants.timeoutShort), "Not all tracked objects were deallocated")
    }
}
