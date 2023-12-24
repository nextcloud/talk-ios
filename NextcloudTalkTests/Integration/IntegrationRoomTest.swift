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
import NextcloudTalk

final class IntegrationRoomTest: TestBase {

    func testRoomList() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        let exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().getRoomsFor(activeAccount, updateStatus: false, modifiedSince: 0) { rooms, error, errorCode in
            XCTAssertEqual(errorCode, 0)
            XCTAssertNil(error)

            // By default, the room list should never be empty, it should contain atleast the talk changelog room
            XCTAssertGreaterThan(rooms?.count ?? 0, 0)

            exp.fulfill()
        }

        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)
    }

    func testRoomCreation() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomName = "Integration Test Room"

        let exp = expectation(description: "\(#function)\(#line)")

        // Create a room
        NCAPIController.sharedInstance().createRoom(for: activeAccount, with: nil, of: kNCRoomTypePublic, andName: roomName) { _, error in
            XCTAssertNil(error)
            exp.fulfill()
        }

        waitForExpectations(timeout: TestConstants.timeoutLong, handler: nil)

        self.checkRoomExists(roomName: roomName, withAccoun: activeAccount)
    }
}
