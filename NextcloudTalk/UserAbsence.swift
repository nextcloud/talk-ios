//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

public struct UserAbsence {

    // See: https://docs.nextcloud.com/server/latest/developer_manual/client_apis/OCS/ocs-out-of-office-api.html
    public var id: Int = 0
    public var userId: String?
    public var firstDay = Date()
    public var lastDay = Date()
    public var status: String
    public var message: String
    public var replacementUserId: String?
    public var replacementUserDisplayName: String?

    public var messageOrStatus: String {
        !message.isEmpty ? message : status
    }

    public var isValid: Bool {
        !message.isEmpty && !status.isEmpty
    }

    public var hasReplacementSet: Bool {
        guard let replacementUserId else { return false }
        return !replacementUserId.isEmpty
    }

    public var replacementName: String {
        replacementUserDisplayName ?? replacementUserId ?? ""
    }

    init(dictionary: [String: Any]) {
        self.id = dictionary["id"] as? Int ?? 0
        self.userId = dictionary["userId"] as? String
        self.status = dictionary["status"] as? String ?? ""
        self.message = dictionary["message"] as? String ?? ""
        self.replacementUserId = dictionary["replacementUserId"] as? String
        self.replacementUserDisplayName = dictionary["replacementUserDisplayName"] as? String

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        if let firstDayString = dictionary["firstDay"] as? String, let date = dateFormatter.date(from: firstDayString) {
            self.firstDay = date
        }

        if let lastDayString = dictionary["lastDay"] as? String, let date = dateFormatter.date(from: lastDayString) {
            self.lastDay = date
        }

    }

    public func asDictionary() -> [String: Any]? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var result: [String: Any] = [
            "firstDay": dateFormatter.string(from: firstDay),
            "lastDay": dateFormatter.string(from: lastDay),
            "status": status,
            "message": message
        ]

        if let replacementUserId, let replacementUserDisplayName {
            result["replacementUserId"] = replacementUserId
            result["replacementUserDisplayName"] = replacementUserDisplayName
        }

        return result
    }
}
