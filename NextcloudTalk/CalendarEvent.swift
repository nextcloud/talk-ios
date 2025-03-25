//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

struct CalendarEvent {

    var calendarAppUrl: String
    var calendarUri: String
    var location: String
    var recurrenceId: String
    var start: Int
    var summary: String
    var uri: String

    init(dictionary: [String: Any]) {
        self.calendarAppUrl = dictionary["calendarAppUrl"] as? String ?? ""
        self.calendarUri = dictionary["calendarUri"] as? String ?? ""
        self.location = dictionary["location"] as? String ?? ""
        self.recurrenceId = dictionary["recurrenceId"] as? String ?? ""
        self.start = dictionary["start"] as? Int ?? -1
        self.summary = dictionary["summary"] as? String ?? ""
        self.uri = dictionary["uri"] as? String ?? ""
    }

    func startDate() -> Date {
        return Date(timeIntervalSince1970: TimeInterval(start))
    }
}
