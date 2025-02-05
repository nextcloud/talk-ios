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
        let calendar = Calendar.current
        let now = Date()

        if eventDate <= now {
            return NSLocalizedString("Now", comment: "Indicates an event happening right now")
        }

        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.locale = Locale.current

        let timeString = timeFormatter.string(from: eventDate)

        if calendar.isDateInToday(eventDate) {
            let todayFormat = NSLocalizedString("Today at %@", comment: "Indicates an event happening today")
            return String(format: todayFormat, timeString)
        }

        if calendar.isDateInTomorrow(eventDate) {
            let tomorrowFormat = NSLocalizedString("Tomorrow at %@", comment: "Indicates an event happening tomorrow")
            return String(format: tomorrowFormat, timeString)
        }

        if let nextWeek = calendar.date(byAdding: .day, value: 7, to: now),
           eventDate < calendar.startOfDay(for: nextWeek) {
            let weekdayFormatter = DateFormatter()
            weekdayFormatter.dateFormat = "EEEE"
            weekdayFormatter.locale = Locale.current

            let weekdayString = weekdayFormatter.string(from: eventDate)
            let weekdayFormat = NSLocalizedString("%@ at %@", comment: "Indicates an event happening on a specific day (e.g Monday at 10:00)")
            return String(format: weekdayFormat, weekdayString, timeString)
        }

        let fullDateFormatter = DateFormatter()
        fullDateFormatter.dateStyle = .medium
        fullDateFormatter.locale = Locale.current

        let dateString = fullDateFormatter.string(from: eventDate)
        let dateFormat = NSLocalizedString("%@ at %@", comment: "Indicates an event happening on a specific day (e.g Monday at 10:00)")

        return String(format: dateFormat, dateString, timeString)
    }
}
