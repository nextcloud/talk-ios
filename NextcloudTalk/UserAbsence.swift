//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class UserAbsence: NSObject {

    // See: https://docs.nextcloud.com/server/latest/developer_manual/client_apis/OCS/ocs-out-of-office-api.html
    public var id: Int = 0
    public var userId: String?
    public var firstDay: String?
    public var lastDay: String?
    public var status: String?
    public var message: String?
    public var replacementUserId: String?
    public var replacementUserDisplayName: String?

    init(dictionary: [String: Any]) {
        super.init()

        self.id = dictionary["id"] as? Int ?? 0
        self.userId = dictionary["userId"] as? String
        self.firstDay = dictionary["firstDay"] as? String
        self.lastDay = dictionary["lastDay"] as? String
        self.status = dictionary["status"] as? String
        self.message = dictionary["message"] as? String
        self.replacementUserId = dictionary["replacementUserId"] as? String
        self.replacementUserDisplayName = dictionary["replacementUserDisplayName"] as? String
    }
}
