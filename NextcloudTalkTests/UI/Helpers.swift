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

    func launchAndLogin() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en-US)"]
        app.launchArguments += ["-AppleLocale", "\"en-US\""]
        app.launchArguments += ["-TestEnvironment"]
        app.launch()

        let accountSwitcherButton = app.buttons["Nextcloud Talk"]
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
        let main = webViewsQuery.otherElements["main"]

        // Wait for the webview to be available
        XCTAssert(main.waitForExistence(timeout: TestConstants.timeoutLong))

        // Wait for the login button to be available and to get enabled/hittable
        let loginButtonWeb = webViewsQuery.buttons["Log in"]
        XCTAssert(loginButtonWeb.waitForExistence(timeout: TestConstants.timeoutLong))
        waitForEnabled(object: loginButtonWeb)
        waitForHittable(object: loginButtonWeb)

        loginButtonWeb.tap()

        XCTAssert(main.waitForExistence(timeout: TestConstants.timeoutLong))

        let usernameTextField = main.descendants(matching: .textField).firstMatch
        let passwordTextField = main.descendants(matching: .secureTextField).firstMatch

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

        grantAccessButton.tap()

        // When the account switcher gets enabled, we have atleast 1 account in the app and are online
        XCTAssert(accountSwitcherButton.waitForExistence(timeout: TestConstants.timeoutLong))
        waitForEnabled(object: accountSwitcherButton)

        return app
    }
}
