//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Testing
@testable import NextcloudTalk

@Suite(.serialized)
final class IntegrationScheduleMeeting: TestBase {

    @Test func `schedule meeting`() async throws {
        try skipWithoutCapability(capability: kCapabilityScheduleMeeting)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = try await createUniqueRoom(prefix: "Schedule Meeting", withAccount: activeAccount)

        let firstCalendar: NCCalendar = await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().getCalendars(forAccount: activeAccount) { calendars in
                continuation.resume(returning: calendars.first!)
            }
        }

        let responseTracker = EventTracker()

        NCAPIController.sharedInstance().createMeeting(
            account: activeAccount,
            token: room.token,
            title: "Title",
            description: "Description",
            start: Int(Date().timeIntervalSince1970 + 60),
            end: Int(Date().timeIntervalSince1970 + 120),
            calendarUri: firstCalendar.calendarUri,
            attendeeIds: nil) { response in
                #expect(response == .success)
                responseTracker.signal()
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
                #expect(response == .startError)
                responseTracker.signal()
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
                #expect(response == .endError)
                responseTracker.signal()
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
                #expect(response == .calendarError)
                responseTracker.signal()
            }

        let allResponded = await wait(timeout: TestConstants.timeoutShort) { responseTracker.signalCount == 4 }
        #expect(allResponded)
    }
}
