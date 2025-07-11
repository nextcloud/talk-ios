//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

public struct MessageThread {

    var id: Int
    var roomToken: String
    var lastMessageId: Int
    var lastActivity: Int
    var numReplies: Int

    init(id: Int, roomToken: String, lastMessageId: Int, lastActivity: Int, numReplies: Int) {
        self.id = id
        self.roomToken = roomToken
        self.lastMessageId = lastMessageId
        self.lastActivity = lastActivity
        self.numReplies = numReplies
    }

    init(dictionary: [String: Any]) {
        self.id = dictionary["id"] as? Int ?? 0
        self.roomToken = dictionary["roomToken"] as? String ?? ""
        self.lastMessageId = dictionary["lastMessageId"] as? Int ?? 0
        self.lastActivity = dictionary["lastActivity"] as? Int ?? 0
        self.numReplies = dictionary["numReplies"] as? Int ?? 0
    }
}
