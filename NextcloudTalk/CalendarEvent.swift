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

    func readableStartTime() -> String {
        let eventDate = Date(timeIntervalSince1970: TimeInterval(start))
        let now = Date()

        // Event happening now
        if eventDate <= now {
            return NSLocalizedString("Now", comment: "Indicates an event happening right now")
        }

        // Event happening following days (except today or tomorrow)
        let calendar = Calendar.current
        if let nextWeek = calendar.date(byAdding: .day, value: 7, to: now),
           !calendar.isDateInToday(eventDate), !calendar.isDateInTomorrow(eventDate),
           eventDate < calendar.startOfDay(for: nextWeek) {
            return eventDate.formatted(
                .dateTime
                .weekday(.wide)
                .hour(.conversationalTwoDigits(amPM: .wide))
                .minute(.defaultDigits))
        }

        // Event happening today, tomorrow or later than a week
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateFormatter.doesRelativeDateFormatting = true

        return dateFormatter.string(from: eventDate)
    }
}
