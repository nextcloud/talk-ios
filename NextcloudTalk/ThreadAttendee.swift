//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

public struct ThreadAttendee {

    var notificationLevel: Int

    init(notificationLevel: Int) {
        self.notificationLevel = notificationLevel
    }

    init(dictionary: [String: Any]) {
        self.notificationLevel = dictionary["notificationLevel"] as? Int ?? 0
    }
}
