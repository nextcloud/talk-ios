//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

public struct ThreadInfo {

    var thread: MessageThread
    var attendee: ThreadAttendee
    var firstMessage: NCChatMessage
    var lastMessage: NCChatMessage?

    init(thread: MessageThread, attendee: ThreadAttendee, firstMessage: NCChatMessage, lastMessage: NCChatMessage) {
        self.thread = thread
        self.attendee = attendee
        self.firstMessage = firstMessage
        self.lastMessage = lastMessage
    }

    init(dictionary: [String: Any]) {
        self.thread = MessageThread(dictionary: dictionary["thread"] as? [String: Any] ?? [:])
        self.attendee = ThreadAttendee(dictionary: dictionary["attendee"] as? [String: Any] ?? [:])
        self.firstMessage = NCChatMessage(dictionary: dictionary["first"] as? [String: Any] ?? [:])
        self.lastMessage = NCChatMessage(dictionary: dictionary["last"] as? [String: Any])
    }
}
