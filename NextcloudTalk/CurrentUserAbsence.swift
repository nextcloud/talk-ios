//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class CurrentUserAbsence: NSObject {

    // See: https://docs.nextcloud.com/server/latest/developer_manual/client_apis/OCS/ocs-out-of-office-api.html
    public var id: String?
    public var userId: String?
    public var startDate: Int?
    public var endDate: Int?
    public var shortMessage: String?
    public var message: String?
    public var replacementUserId: String?
    public var replacementUserDisplayName: String?

    init(dictionary: [String: Any]) {
        super.init()

        self.id = dictionary["id"] as? String
        self.userId = dictionary["userId"] as? String
        self.startDate = dictionary["startDate"] as? Int
        self.endDate = dictionary["endDate"] as? Int
        self.shortMessage = dictionary["status"] as? String
        self.message = dictionary["message"] as? String
        self.replacementUserId = dictionary["replacementUserId"] as? String
        self.replacementUserDisplayName = dictionary["replacementUserDisplayName"] as? String
    }
}
