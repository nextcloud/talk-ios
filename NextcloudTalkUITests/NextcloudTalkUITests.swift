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

final class NextcloudTalkUITests: XCTestCase {

    let timeoutLong: Double = 60
    let timeoutShort: Double = 15
    let server = "http://localhost:8080"
    let username = "admin"
    let password = "admin"

    override func setUpWithError() throws {
        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func waitForEnabled(object: Any?) {
        let enabledPredicate = NSPredicate(format: "enabled == true")
        expectation(for: enabledPredicate, evaluatedWith: object, handler: nil)
        waitForExpectations(timeout: timeoutLong, handler: nil)
    }

    func waitForHittable(object: Any?) {
        let enabledPredicate = NSPredicate(format: "hittable == true")
        expectation(for: enabledPredicate, evaluatedWith: object, handler: nil)
        waitForExpectations(timeout: timeoutLong, handler: nil)
    }

    func launchAndLogin() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en-US)"]
        app.launchArguments += ["-AppleLocale", "\"en-US\""]
        app.launchArguments += ["-TestEnvironment"]
        app.launch()

        let accountSwitcherButton = app.buttons["Nextcloud Talk"]

        // Wait shortly until the app is fully started
        _ = accountSwitcherButton.waitForExistence(timeout: timeoutShort)

        // When the account switcher button exists, we have atleast one account configured
        if accountSwitcherButton.exists {
            return app
        }

        let serverAddressHttpsTextField = app.textFields["Server address https://…"]
        XCTAssert(serverAddressHttpsTextField.waitForExistence(timeout: timeoutLong))
        serverAddressHttpsTextField.tap()
        serverAddressHttpsTextField.typeText(server)

        let loginButton = app.buttons["Log in"]
        XCTAssert(loginButton.waitForExistence(timeout: timeoutLong))
        loginButton.tap()

        let webViewsQuery = app.webViews.webViews.webViews
        let loginButton2 = webViewsQuery.buttons["Log in"]

        // Wait for the login button to be available and to get enabled
        XCTAssert(loginButton2.waitForExistence(timeout: timeoutLong))
        waitForEnabled(object: loginButton2)

        loginButton2.tap()

        let main = webViewsQuery.otherElements["main"]
        XCTAssert(main.waitForExistence(timeout: timeoutLong))

        let usernameTextField = main.descendants(matching: .textField).firstMatch
        let passwordTextField = main.descendants(matching: .secureTextField).firstMatch

        XCTAssert(usernameTextField.waitForExistence(timeout: timeoutLong))
        XCTAssert(passwordTextField.waitForExistence(timeout: timeoutLong))

        usernameTextField.tap()
        usernameTextField.typeText(username + "\n")

        passwordTextField.tap()
        passwordTextField.typeText(password + "\n")

        let grantAccessButton = webViewsQuery.buttons["Grant access"]
        XCTAssert(grantAccessButton.waitForExistence(timeout: timeoutLong))
        waitForEnabled(object: grantAccessButton)
        waitForHittable(object: grantAccessButton)

        grantAccessButton.tap()

        // When the account switcher gets enabled, we have atleast 1 account in the app and are online
        XCTAssert(accountSwitcherButton.waitForExistence(timeout: timeoutLong))
        waitForEnabled(object: accountSwitcherButton)

        return app
    }

    // Tests are done in alphabetical order, so we want to always test login first
    func test_AAAA_Login() {
        let app = launchAndLogin()

        // Check if the profile button is available
        let profileButton = app.buttons["User profile and settings"]
        XCTAssert(profileButton.waitForExistence(timeout: timeoutLong))

        // Open profile menu
        profileButton.tap()

        // At this point we should be logged in, so check if username and server is displayed somewhere
        XCTAssert(app.staticTexts[server].waitForExistence(timeout: timeoutShort))
        XCTAssert(app.staticTexts[username].waitForExistence(timeout: timeoutShort))
    }

    func testCreateConversation() {
        let app = launchAndLogin()
        let newConversationName = "Test conversation"

        app.navigationBars["Nextcloud Talk"].buttons["Create a new conversation"].tap()
        XCTAssert(app.tables.cells.staticTexts["Create a new group conversation"].waitForExistence(timeout: timeoutShort))
        XCTAssert(app.tables.cells.staticTexts["Create a new public conversation"].waitForExistence(timeout: timeoutShort))
        XCTAssert(app.tables.cells.staticTexts["Show list of open conversations"].waitForExistence(timeout: timeoutShort))
        app.tables.cells.staticTexts["Create a new group conversation"].tap()
        app.navigationBars["RoomCreationTableView"].buttons["Next"].tap()
        app.typeText(newConversationName)
        app.navigationBars["New group conversation"].buttons["Create"].tap()

        let chatNavBar = app.navigationBars["NCChatView"]

        // Wait for titleView
        let chatTitleView = chatNavBar.textViews.staticTexts[newConversationName]
        XCTAssert(chatNavBar.waitForExistence(timeout: timeoutLong))

        // Open conversation settings
        chatTitleView.tap()

        // Check if if the name of the conversation is shown
        XCTAssert(app.textFields[newConversationName].waitForExistence(timeout: timeoutLong))

        // Go back to conversation list
        app.navigationBars["Conversation settings"].buttons["Back"].tap()
        chatNavBar.buttons["Back"].tap()

        // Check if the conversation appears in the conversation list
        XCTAssert(app.tables.cells.staticTexts[newConversationName].waitForExistence(timeout: timeoutLong))
    }

    func testChatViewControllerDeallocation() {
        let app = launchAndLogin()
        let newConversationName = "DeAllocTest"

        // Create a new test conversion
        app.navigationBars["Nextcloud Talk"].buttons["Create a new conversation"].tap()
        XCTAssert(app.tables.cells.staticTexts["Create a new group conversation"].waitForExistence(timeout: timeoutShort))
        XCTAssert(app.tables.cells.staticTexts["Create a new public conversation"].waitForExistence(timeout: timeoutShort))
        XCTAssert(app.tables.cells.staticTexts["Show list of open conversations"].waitForExistence(timeout: timeoutShort))
        app.tables.cells.staticTexts["Create a new group conversation"].tap()
        app.navigationBars["RoomCreationTableView"].buttons["Next"].tap()
        app.typeText(newConversationName)
        app.navigationBars["New group conversation"].buttons["Create"].tap()

        // Check if we have one chat view controller allocated
        XCTAssert(app.staticTexts["ChatVC: 1 / CallVC: 0"].waitForExistence(timeout: timeoutShort))

        // Send a test message
        let testMessage = "TestMessage"
        let toolbar = app.toolbars["Toolbar"]
        let textView = toolbar.textViews["Write message, @ to mention someone …"]
        XCTAssert(textView.waitForExistence(timeout: timeoutShort))
        textView.tap()
        app.typeText(testMessage)
        let sendMessageButton = toolbar.buttons["Send message"]
        sendMessageButton.tap()

        // Wait for temporary message to be replaced
        sleep(5)

        // Open context menu
        let tables = app.tables
        XCTAssert(tables.staticTexts[username].waitForExistence(timeout: timeoutShort))
        let message = tables.staticTexts[username]
        message.press(forDuration: 2.0)

        // Add a reaction to close the context menu
        XCTAssert(app.staticTexts["👍"].waitForExistence(timeout: timeoutShort))
        app.staticTexts["👍"].tap()

        // Go back to the main view controller
        let chatNavBar = app.navigationBars["NCChatView"]
        chatNavBar.buttons["Back"].tap()

        // Check if all chat view controllers are deallocated
        XCTAssert(app.staticTexts["ChatVC: 0 / CallVC: 0"].waitForExistence(timeout: timeoutShort))
    }
}
