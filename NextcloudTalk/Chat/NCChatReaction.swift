//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

@objcMembers
public class NCChatReaction: NSObject {

    public var reaction: String
    public var count: Int
    public var userReacted: Bool = false
    public var state: NCChatReactionState

    init(reaction: String, count: Int = 0, userReacted: Bool = false, state: NCChatReactionState = .set) {
        self.reaction = reaction
        self.count = count
        self.userReacted = userReacted
        self.state = state
    }

}
