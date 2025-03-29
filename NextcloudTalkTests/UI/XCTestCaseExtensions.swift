//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import XCTest

extension XCTestCase {

    @discardableResult
    func waitForReady(object: XCUIElement, timeout: Double = TestConstants.timeoutShort) -> XCUIElement {
        let enabledPredicate = NSPredicate(format: "exists == true AND enabled == true AND hittable == true")
        expectation(for: enabledPredicate, evaluatedWith: object, handler: nil)
        waitForExpectations(timeout: timeout, handler: nil)

        return object
    }

    // Based on https://stackoverflow.com/a/47947315
    @discardableResult
    func waitForEitherElementToExist(_ elementA: XCUIElement, _ elementB: XCUIElement, _ timeout: TimeInterval) -> XCUIElement? {
        let startTime = NSDate.timeIntervalSinceReferenceDate
        while !elementA.exists && !elementB.exists { // while neither element exists
            if NSDate.timeIntervalSinceReferenceDate - startTime > timeout {
                XCTFail("Timed out waiting for either element to exist.")
                break
            }
            sleep(1)
        }

        if elementA.exists { return elementA }
        if elementB.exists { return elementB }
        return nil
    }

    @discardableResult
    func launchAndLogin() -> XCUIApplication {
        let app = XCUIApplication()

        // Only start the app once for our tests
        if app.state == .notRunning {
            app.launchArguments += ["-AppleLanguages", "(en-US)"]
            app.launchArguments += ["-AppleLocale", "\"en-US\""]
            app.launchArguments += ["-TestEnvironment"]
            app.launch()
        }

        let accountSwitcherButton = app.buttons["LoadedProfileButton"]
        let serverAddressHttpsTextField = app.textFields["Server address https://…"]

        // Wait shortly until the app is fully started
        let foundElement = waitForEitherElementToExist(accountSwitcherButton, serverAddressHttpsTextField, TestConstants.timeoutLong)
        XCTAssertNotNil(foundElement)

        // When the account switcher button exists, we have atleast one account configured
        if foundElement == accountSwitcherButton {
            return app
        }

        serverAddressHttpsTextField.tap()
        serverAddressHttpsTextField.typeText(TestConstants.server)

        let loginButton = app.buttons["Log in"]
        XCTAssert(loginButton.waitForExistence(timeout: TestConstants.timeoutLong))
        loginButton.tap()

        let webViewsQuery = app.webViews.webViews.webViews

        // Wait for the login button to be available and to get enabled/hittable
        let loginButtonWeb = webViewsQuery.buttons["Log in"]
        waitForReady(object: loginButtonWeb, timeout: TestConstants.timeoutLong)

        loginButtonWeb.tap()

        let usernameTextField = webViewsQuery.descendants(matching: .textField).firstMatch
        let passwordTextField = webViewsQuery.descendants(matching: .secureTextField).firstMatch

        XCTAssert(usernameTextField.waitForExistence(timeout: TestConstants.timeoutLong))
        XCTAssert(passwordTextField.waitForExistence(timeout: TestConstants.timeoutLong))

        usernameTextField.tap()
        usernameTextField.typeText(TestConstants.username + "\n")

        passwordTextField.tap()
        passwordTextField.typeText(TestConstants.password + "\n")

        let accountAccess = webViewsQuery.staticTexts["Account access"]
        XCTAssert(accountAccess.waitForExistence(timeout: TestConstants.timeoutLong))

        let grantAccessButton = webViewsQuery.buttons["Grant access"]
        waitForReady(object: grantAccessButton, timeout: TestConstants.timeoutLong)

        // TODO: Find a better way to reliable detect if the grant access button is tappable
        sleep(5)

        grantAccessButton.tap()

        // When the account switcher gets enabled, we have atleast 1 account in the app and are online
        waitForReady(object: accountSwitcherButton, timeout: TestConstants.timeoutLong)

        return app
    }

    func createConversation(for app: XCUIApplication, with newConversationName: String) {
        app.navigationBars["Nextcloud Talk"].buttons["Create or join a conversation"].tap()

        waitForReady(object: app.tables.cells.staticTexts["Create a new conversation"]).tap()

        let newConversationNavBar = app.navigationBars["New conversation"]
        XCTAssert(newConversationNavBar.waitForExistence(timeout: TestConstants.timeoutShort))
        app.typeText(newConversationName)
        newConversationNavBar.buttons["Create"].tap()
    }
}
