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

    // Every test has to release all tracked objects (controllers, calls, chats) once we are back at the conversation list
    private func checkDeallocation() {
        let app = XCUIApplication()
        guard app.state == .runningForeground else { return }

        let chatNavBar = app.navigationBars["NextcloudTalk.ChatView"]
        if chatNavBar.exists {
            chatNavBar.buttons["Conversations"].tap()
        }

        XCTAssert(app.staticTexts["{}"].waitForExistence(timeout: TestConstants.timeoutShort), "Not all tracked objects were deallocated")
    }
}
