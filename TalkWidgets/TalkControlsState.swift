//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

// What the Control Center controls and the status widget show: whether there's a call and the
// microphone is muted, and the user status of the active account. The app writes it into the
// shared app group, the widget extension only reads it.
// This file is part of the app and of the widget extension.
struct TalkControlsState: Codable, Equatable {

    var isInCall = false
    var isMicrophoneMuted = false
    // One of online, away, dnd, invisible or offline, nil when unknown or no account is logged in
    var userStatus: String?

    static let muteMicrophoneControlKind = "MuteMicrophoneControl"
    static let doNotDisturbControlKind = "DoNotDisturbControl"
    static let newConversationControlKind = "NewConversationControl"
    static let statusWidgetKind = "StatusWidget"

    private static let userDefaultsKey = "talkControlsState"

    static func load(appGroupIdentifier: String) -> TalkControlsState {
        guard let data = UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: userDefaultsKey),
              let state = try? JSONDecoder().decode(TalkControlsState.self, from: data)
        else { return TalkControlsState() }

        return state
    }

    func save(appGroupIdentifier: String) {
        guard let data = try? JSONEncoder().encode(self) else { return }

        UserDefaults(suiteName: appGroupIdentifier)?.set(data, forKey: Self.userDefaultsKey)
    }

    static func remove(appGroupIdentifier: String) {
        UserDefaults(suiteName: appGroupIdentifier)?.removeObject(forKey: userDefaultsKey)
    }
}
