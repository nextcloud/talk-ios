//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import XCTest

final class AAAALoginTest: XCTestCase {

    override func setUpWithError() throws {
        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
    }

    // Tests are done in alphabetical order, so we want to always test login first
    func test_Login() {
        let app = launchAndLogin()

        // Check if the profile button is available
        let profileButton = app.buttons["LoadedProfileButton"]
        XCTAssert(profileButton.waitForExistence(timeout: TestConstants.timeoutLong))

        // Open profile menu
        profileButton.tap()

        // At this point we should be logged in, so check if username and server is displayed somewhere
        XCTAssert(app.buttons["Settings"].waitForExistence(timeout: TestConstants.timeoutShort))
        XCTAssert(app.buttons["Add account"].waitForExistence(timeout: TestConstants.timeoutShort))
    }

}
