//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import ActivityKit
import Foundation

// Shared between the app, which starts and updates the Live Activity, and the widget extension, which renders it
struct CallActivityAttributes {

    enum Status: String, Codable, Hashable {
        case connecting
        case waitingForParticipants
        case reconnecting
        case inCall
    }

    struct ContentState: Codable, Hashable {
        var status: Status
        var isAudioMuted: Bool
        // Only set for group conversations
        var participantCount: Int?
        var callStartDate: Date?
        // Absolute path of a small avatar image in the shared app group container
        var avatarPath: String?
    }

    var roomToken: String
    var roomName: String
    var isVideoCall: Bool
}

@available(iOS 16.1, *)
extension CallActivityAttributes: ActivityAttributes {}
