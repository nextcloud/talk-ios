//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

extension Date {
    func format(dateStyle: DateFormatter.Style = .none, timeStyle: DateFormatter.Style = .none) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = dateStyle
        dateFormatter.timeStyle = timeStyle

        return dateFormatter.string(from: self)
    }

    func futureRelativeTime() -> String {
        let now = Date()

        // Event happening following days (except today or tomorrow)
        let calendar = Calendar.current
        if let nextWeek = calendar.date(byAdding: .day, value: 7, to: now),
           !calendar.isDateInToday(self), !calendar.isDateInTomorrow(self),
           self < calendar.startOfDay(for: nextWeek) {
            return self.formatted(
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

        return dateFormatter.string(from: self)
    }
}
