//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import XCTest

extension XCTestCase {

    func waitForEnabled(object: Any?) {
        let enabledPredicate = NSPredicate(format: "enabled == true")
        expectation(for: enabledPredicate, evaluatedWith: object, handler: nil)
        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)
    }

    func waitForHittable(object: Any?) {
        let enabledPredicate = NSPredicate(format: "hittable == true")
        expectation(for: enabledPredicate, evaluatedWith: object, handler: nil)
        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)
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
        app.launchArguments += ["-AppleLanguages", "(en-US)"]
        app.launchArguments += ["-AppleLocale", "\"en-US\""]
        app.launchArguments += ["-TestEnvironment"]
        app.launch()

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
        XCTAssert(loginButtonWeb.waitForExistence(timeout: TestConstants.timeoutLong))
        waitForEnabled(object: loginButtonWeb)
        waitForHittable(object: loginButtonWeb)

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
        XCTAssert(grantAccessButton.waitForExistence(timeout: TestConstants.timeoutLong))
        waitForEnabled(object: grantAccessButton)
        waitForHittable(object: grantAccessButton)

        // TODO: Find a better way to reliable detect if the grant access button is tappable
        sleep(5)

        grantAccessButton.tap()

        // When the account switcher gets enabled, we have atleast 1 account in the app and are online
        XCTAssert(accountSwitcherButton.waitForExistence(timeout: TestConstants.timeoutLong))
        waitForEnabled(object: accountSwitcherButton)

        return app
    }

    func createConversation(for app: XCUIApplication, with newConversationName: String) {
        app.navigationBars["Nextcloud Talk"].buttons["Create or join a conversation"].tap()

        let createNewConversationCell = app.tables.cells.staticTexts["Create a new conversation"]
        XCTAssert(createNewConversationCell.waitForExistence(timeout: TestConstants.timeoutShort))
        createNewConversationCell.tap()

        let newConversationNavBar = app.navigationBars["New conversation"]
        XCTAssert(newConversationNavBar.waitForExistence(timeout: TestConstants.timeoutShort))
        app.typeText(newConversationName)
        newConversationNavBar.buttons["Create"].tap()
    }
}
