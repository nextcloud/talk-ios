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

    let timeoutSeconds: Double = 60
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
        waitForExpectations(timeout: timeoutSeconds, handler: nil)
    }

    func waitForHittable(object: Any?) {
        let enabledPredicate = NSPredicate(format: "hittable == true")
        expectation(for: enabledPredicate, evaluatedWith: object, handler: nil)
        waitForExpectations(timeout: timeoutSeconds, handler: nil)
    }

    func launchAndLogin() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en-US)"]
        app.launchArguments += ["-AppleLocale", "\"en-US\""]
        app.launch()

        let accountSwitcherButton = app.buttons["Nextcloud Talk"]

        // Wait shortly until the app is fully started
        _ = accountSwitcherButton.waitForExistence(timeout: timeoutShort)

        if accountSwitcherButton.exists, accountSwitcherButton.isEnabled {
            return app
        }

        let serverAddressHttpsTextField = app.textFields["Server address https://…"]
        XCTAssert(serverAddressHttpsTextField.waitForExistence(timeout: timeoutSeconds))
        serverAddressHttpsTextField.tap()
        serverAddressHttpsTextField.typeText(server)

        let loginButton = app.buttons["Log in"]
        XCTAssert(loginButton.waitForExistence(timeout: timeoutSeconds))
        loginButton.tap()

        let webViewsQuery = app.webViews.webViews.webViews
        let loginButton2 = webViewsQuery.buttons["Log in"]

        // Wait for the login button to be available and to get enabled
        XCTAssert(loginButton2.waitForExistence(timeout: timeoutSeconds))
        waitForEnabled(object: loginButton2)

        loginButton2.tap()

        let main = webViewsQuery.otherElements["main"]
        XCTAssert(main.waitForExistence(timeout: timeoutSeconds))

        let usernameTextField = main.descendants(matching: .textField).firstMatch
        let passwordTextField = main.descendants(matching: .secureTextField).firstMatch

        XCTAssert(usernameTextField.waitForExistence(timeout: timeoutSeconds))
        XCTAssert(passwordTextField.waitForExistence(timeout: timeoutSeconds))

        usernameTextField.tap()
        usernameTextField.typeText(username + "\n")

        passwordTextField.tap()
        passwordTextField.typeText(password + "\n")

        let grantAccessButton = webViewsQuery.buttons["Grant access"]
        XCTAssert(grantAccessButton.waitForExistence(timeout: timeoutSeconds))
        waitForEnabled(object: grantAccessButton)
        waitForHittable(object: grantAccessButton)

        grantAccessButton.tap()

        // When the account switcher gets enabled, we have atleast 1 account in the app and are online
        XCTAssert(accountSwitcherButton.waitForExistence(timeout: timeoutSeconds))
        waitForEnabled(object: accountSwitcherButton)

        return app
    }

    // Tests are done in alphabetical order, so we want to always test login first
    func test_AAAA_Login() {
        let app = launchAndLogin()

        // Check if the profile button is available
        let profileButton = app.buttons["User profile and settings"]
        XCTAssert(profileButton.waitForExistence(timeout: timeoutSeconds))

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
        app.tables.cells.staticTexts["Create a new group conversation"].tap()
        app.navigationBars["RoomCreationTableView"].buttons["Next"].tap()
        app.typeText(newConversationName)
        app.navigationBars["New group conversation"].buttons["Create"].tap()

        let chatNavBar = app.navigationBars["NCChatView"]

        // Wait for titleView
        let chatTitleView = chatNavBar.textViews.staticTexts[newConversationName]
        XCTAssert(chatNavBar.waitForExistence(timeout: timeoutShort))

        // Open conversation settings
        chatTitleView.tap()

        // Check if if the name of the conversation is shown
        XCTAssert(app.textFields[newConversationName].waitForExistence(timeout: timeoutShort))

        // Go back to conversation list
        app.navigationBars["Conversation settings"].buttons["Back"].tap()
        chatNavBar.buttons["Back"].tap()

        // Check if the conversation appears in the conversation list
        XCTAssert(app.tables.cells.staticTexts[newConversationName].waitForExistence(timeout: timeoutShort))
    }
}
