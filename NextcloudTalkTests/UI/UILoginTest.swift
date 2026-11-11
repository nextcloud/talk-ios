//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import XCTest

final class UILoginTest: UITestCase {

    func testLogin() {
        let app = launchApp(with: ["-TestResetAccounts"])

        let serverAddressHttpsTextField = app.textFields["Server address https://…"]
        waitForReady(object: serverAddressHttpsTextField, timeout: TestConstants.timeoutLong).tap()
        serverAddressHttpsTextField.typeText(TestConstants.server)

        let loginButton = app.buttons["Log in"]
        XCTAssert(loginButton.waitForExistence(timeout: TestConstants.timeoutLong))
        loginButton.tap()

        // The authentication session shows the login page out of process
        let loginWebview = XCUIApplication(bundleIdentifier: "com.apple.SafariViewService").webViews.firstMatch
        waitForReady(object: loginWebview, timeout: TestConstants.timeoutLong)

        // Wait for the login button to be available and to get enabled/hittable
        // Newer servers render the button as a plain link without a button role
        let loginButtonWeb = waitForEitherElementToExist(loginWebview.buttons["Log in"], loginWebview.links["Log in"], TestConstants.timeoutLong)
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
        waitForReady(object: app.buttons["LoadedProfileButton"], timeout: TestConstants.timeoutLong)
    }

}
