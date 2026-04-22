//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

@objc
public enum NCAPIVersion: Int, Comparable {

    case APIv1 = 1
    case APIv2 = 2
    case APIv3 = 3
    case APIv4 = 4

    init(forType type: NCAPIType, withAccount account: TalkAccount) {
        switch type {
        case .conversation, .call:
            self = .APIv4
        case .chat, .reactions, .polls, .breakoutRooms, .federation, .ban, .bots, .recording, .settings, .avatar:
            self = .APIv1
        case .signaling:
            self = .APIv3
        }
    }

    public static func < (lhs: NCAPIVersion, rhs: NCAPIVersion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
