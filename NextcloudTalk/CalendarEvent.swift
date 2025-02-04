//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class CalendarEvent: NSObject {

    public var calendarAppUrl: String
    public var calendarUri: String
    public var location: String
    public var recurrenceId: String
    public var start: Int
    public var summary: String
    public var uri: String

    init(dictionary: [String: Any]) {
        self.calendarAppUrl = dictionary["calendarAppUrl"] as? String ?? ""
        self.calendarUri = dictionary["calendarUri"] as? String ?? ""
        self.location = dictionary["location"] as? String ?? ""
        self.recurrenceId = dictionary["recurrenceId"] as? String ?? ""
        self.start = dictionary["start"] as? Int ?? -1
        self.summary = dictionary["summary"] as? String ?? ""
        self.uri = dictionary["uri"] as? String ?? ""

        super.init()
    }
}
