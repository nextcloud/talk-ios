//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

public struct CalendarEvent {

    var calendarAppUrl: String
    var calendarUri: String
    var location: String
    var recurrenceId: String
    var start: Int
    var end: Int?
    var summary: String
    var uri: String

    init(calendarAppUrl: String, calendarUri: String, location: String, recurrenceId: String, start: Int, end: Int? = nil, summary: String, uri: String) {
        self.calendarAppUrl = calendarAppUrl
        self.calendarUri = calendarUri
        self.location = location
        self.recurrenceId = recurrenceId
        self.start = start
        self.end = end
        self.summary = summary
        self.uri = uri
    }

    init(dictionary: [String: Any]) {
        self.calendarAppUrl = dictionary["calendarAppUrl"] as? String ?? ""
        self.calendarUri = dictionary["calendarUri"] as? String ?? ""
        self.location = dictionary["location"] as? String ?? ""
        self.recurrenceId = dictionary["recurrenceId"] as? String ?? ""
        self.start = dictionary["start"] as? Int ?? -1
        self.summary = dictionary["summary"] as? String ?? ""
        self.uri = dictionary["uri"] as? String ?? ""
    }

    private func startDate() -> Date {
        return Date(timeIntervalSince1970: TimeInterval(start))
    }

    private func endDate() -> Date? {
        guard let end else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(end))
    }

    public var isFutureEvent: Bool {
        let nowTimestamp = Int(Date().timeIntervalSince1970)
        return start >= nowTimestamp
    }

    public var isPastEvent: Bool {
        let nowTimestamp = Int(Date().timeIntervalSince1970)

        if let end {
            return end <= nowTimestamp
        }

        return start <= nowTimestamp
    }

    public var isOngoingEvent: Bool {
        let nowTimestamp = Int(Date().timeIntervalSince1970)

        if let end {
            return start < nowTimestamp && end > nowTimestamp
        }

        // Fallback to 30 minute default
        return start < nowTimestamp && (start + 30 * 60) < nowTimestamp
    }

    func readableStartTime() -> String {
        let now = Date()
        let startDate = self.startDate()

        if let endDate = self.endDate() {
            // When we have an end date, we can check if the meeting is actually ongoing
            if endDate <= now {
                return NSLocalizedString("Meeting ended", comment: "")
            } else if startDate <= now {
                return NSLocalizedString("Now", comment: "Indicates an event happening right now")
            }
        } else {
            // Fallback for "upcoming events" that don't serve an end date on the API
            if startDate <= now {
                return NSLocalizedString("Now", comment: "Indicates an event happening right now")
            }
        }

        return startDate.futureRelativeTime()
    }

}
