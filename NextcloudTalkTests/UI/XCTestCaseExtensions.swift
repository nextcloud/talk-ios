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

    @discardableResult
    func waitForCount(query: XCUIElementQuery, count: Int, timeout: Double = TestConstants.timeoutShort) -> XCUIElementQuery {
        let enabledPredicate = NSPredicate(format: "count == %d", count)
        expectation(for: enabledPredicate, evaluatedWith: query, handler: nil)
        waitForExpectations(timeout: timeout, handler: nil)

        return query
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
            usleep(200_000)
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
    func launchApp(with arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()

        app.launchArguments += ["-AppleLanguages", "(en-US)"]
        app.launchArguments += ["-AppleLocale", "\"en-US\""]
        app.launchArguments += ["-TestEnvironment"]
        app.launchArguments += arguments
        app.launch()

        return app
    }

    // Starts with only the test account configured, independent of what previous tests left behind
    @discardableResult
    func launchAndLogin() -> XCUIApplication {
        let app = launchApp(with: [
            "-TestAccountServer", TestConstants.server,
            "-TestAccountUser", TestConstants.username,
            "-TestAccountPassword", TestConstants.password
        ])

        // When the account switcher gets enabled, we have atleast 1 account in the app and are online
        waitForReady(object: app.buttons["LoadedProfileButton"], timeout: TestConstants.timeoutLong)

        return app
    }

    func createConversation(for app: XCUIApplication, with newConversationName: String) {
        waitForReady(object: app.buttons["Create or join a conversation"]).tap()
        waitForReady(object: app.tables.cells.staticTexts["Create a new conversation"]).tap()

        let newConversationNavBar = app.navigationBars["New conversation"]
        XCTAssert(newConversationNavBar.waitForExistence(timeout: TestConstants.timeoutShort))
        app.typeText(newConversationName)

        waitForReady(object: newConversationNavBar.buttons["Create"]).tap()
    }
}
