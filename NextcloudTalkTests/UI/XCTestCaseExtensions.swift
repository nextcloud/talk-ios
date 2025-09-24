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
    func waitForEitherElementToExist(_ elementA: XCUIElement, _ elementB: XCUIElement, _ timeout: TimeInterval) -> XCUIElement {
        let startTime = NSDate.timeIntervalSinceReferenceDate
        while !(elementA.exists && elementA.isHittable) && !(elementB.exists && elementB.isHittable) { // while neither element exists
            if NSDate.timeIntervalSinceReferenceDate - startTime > timeout {
                XCTFail("Timed out waiting for either element to exist.")
                break
            }
            usleep(500)
        }

        if elementA.exists {
            return elementA
        }

        if !elementB.exists {
            XCTFail("Unknown failure while waiting for either element to exist.")
        }

        return elementB
    }

    @discardableResult
    func launchAndLogin() -> XCUIApplication {
        let app = XCUIApplication()

        app.launchArguments += ["-AppleLanguages", "(en-US)"]
        app.launchArguments += ["-AppleLocale", "\"en-US\""]
        app.launchArguments += ["-TestEnvironment"]
        app.launch()

        let accountSwitcherButton = app.buttons["LoadedProfileButton"]
        let serverAddressHttpsTextField = app.textFields["Server address https://…"]

        // Wait shortly until the app is fully started
        let foundElement = waitForEitherElementToExist(accountSwitcherButton, serverAddressHttpsTextField, TestConstants.timeoutLong)

        // When the account switcher button exists, we have atleast one account configured
        if foundElement == accountSwitcherButton {
            return app
        }

        serverAddressHttpsTextField.tap()
        serverAddressHttpsTextField.typeText(TestConstants.server)

        let loginButton = app.buttons["Log in"]
        XCTAssert(loginButton.waitForExistence(timeout: TestConstants.timeoutLong))
        loginButton.tap()

        let loginWebview = app.webViews["interactiveWebLoginView"]
        waitForReady(object: loginWebview, timeout: TestConstants.timeoutLong)

        // Wait for the login button to be available and to get enabled/hittable
        let loginButtonWeb = loginWebview.buttons["Log in"]
        waitForReady(object: loginButtonWeb, timeout: TestConstants.timeoutLong)

        loginButtonWeb.tap()

        let usernameTextField = loginWebview.descendants(matching: .textField).firstMatch
        let passwordTextField = loginWebview.descendants(matching: .secureTextField).firstMatch

        XCTAssert(usernameTextField.waitForExistence(timeout: TestConstants.timeoutLong))
        XCTAssert(passwordTextField.waitForExistence(timeout: TestConstants.timeoutLong))

        usernameTextField.tap()
        usernameTextField.typeText(TestConstants.username + "\n")

        passwordTextField.tap()
        passwordTextField.typeText(TestConstants.password + "\n")

        let accountAccess = loginWebview.staticTexts["Account access"]
        XCTAssert(accountAccess.waitForExistence(timeout: TestConstants.timeoutLong))

        let grantAccessButton = loginWebview.buttons["Grant access"]
        waitForReady(object: grantAccessButton, timeout: TestConstants.timeoutLong)

        // Wait again for the webview to be ready
        waitForReady(object: loginWebview)

        grantAccessButton.tap()

        // When the account switcher gets enabled, we have atleast 1 account in the app and are online
        waitForReady(object: accountSwitcherButton, timeout: TestConstants.timeoutLong)

        return app
    }

    func createConversation(for app: XCUIApplication, with newConversationName: String) {
        waitForReady(object: app.buttons["Create or join a conversation"]).tap()
        waitForReady(object: app.tables.cells.staticTexts["Create a new conversation"]).tap()

        let newConversationNavBar = app.navigationBars["New conversation"]
        XCTAssert(newConversationNavBar.waitForExistence(timeout: TestConstants.timeoutShort))
        app.typeText(newConversationName)
        newConversationNavBar.buttons["Create"].tap()
    }
}
