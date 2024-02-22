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
        XCTAssert(app.buttons[TestConstants.username].waitForExistence(timeout: TestConstants.timeoutShort))
    }

}
