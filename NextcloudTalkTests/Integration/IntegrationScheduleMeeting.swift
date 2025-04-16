//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
import Foundation
@testable import NextcloudTalk

final class IntegrationScheduleMeeting: TestBase {

    func testScheduleMeeting() async throws {
        try skipWithoutCapability(capability: kCapabilityScheduleMeeting)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = try await createUniqueRoom(prefix: "Schedule Meeting", withAccount: activeAccount)

        var firstCalendar: NCCalendar!
        var exp = expectation(description: "\(#function)\(#line)")

        NCAPIController.sharedInstance().getCalendars(forAccount: activeAccount) { calendars in
            firstCalendar = calendars.first!
            exp.fulfill()
        }

        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)

        exp = expectation(description: "\(#function)\(#line)")
        exp.expectedFulfillmentCount = 4

        NCAPIController.sharedInstance().createMeeting(
            account: activeAccount,
            token: room.token,
            title: "Title",
            description: "Description",
            start: Int(Date().timeIntervalSince1970 + 60),
            end: Int(Date().timeIntervalSince1970 + 120),
            calendarUri: firstCalendar.calendarUri,
            attendeeIds: nil) { response in
                XCTAssertEqual(response, .success)
                exp.fulfill()
            }

        NCAPIController.sharedInstance().createMeeting(
            account: activeAccount,
            token: room.token,
            title: "Title",
            description: "Description",
            start: Int(Date().timeIntervalSince1970 - 1200),
            end: Int(Date().timeIntervalSince1970),
            calendarUri: firstCalendar.calendarUri,
            attendeeIds: nil) { response in
                XCTAssertEqual(response, .startError)
                exp.fulfill()
            }

        NCAPIController.sharedInstance().createMeeting(
            account: activeAccount,
            token: room.token,
            title: "Title",
            description: "Description",
            start: Int(Date().timeIntervalSince1970 + 60),
            end: Int(Date().timeIntervalSince1970 - 60),
            calendarUri: firstCalendar.calendarUri,
            attendeeIds: nil) { response in
                XCTAssertEqual(response, .endError)
                exp.fulfill()
            }

        NCAPIController.sharedInstance().createMeeting(
            account: activeAccount,
            token: room.token,
            title: "Title",
            description: "Description",
            start: Int(Date().timeIntervalSince1970 + 60),
            end: Int(Date().timeIntervalSince1970 + 120),
            calendarUri: "abc",
            attendeeIds: nil) { response in
                XCTAssertEqual(response, .calendarError)
                exp.fulfill()
            }

        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)
    }
}
