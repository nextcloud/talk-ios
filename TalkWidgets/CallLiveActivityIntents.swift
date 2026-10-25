//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AppIntents
import Foundation

enum CallLiveActivityAction {
    case toggleAudio
    case hangUp
}

// The intents are compiled into the app and the widget extension, but a LiveActivityIntent always runs in the app process.
// The app registers the handler, so it is never called inside the extension.
@MainActor
enum CallLiveActivityActionHandler {
    static var handler: ((CallLiveActivityAction, String) -> Void)?

    static func perform(_ action: CallLiveActivityAction, forRoomToken roomToken: String) {
        handler?(action, roomToken)
    }
}

@available(iOS 17.0, *)
struct ToggleCallAudioIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Toggle microphone"
    static let isDiscoverable = false

    @Parameter(title: "Conversation token")
    var roomToken: String

    init() {}

    init(roomToken: String) {
        self.roomToken = roomToken
    }

    func perform() async throws -> some IntentResult {
        await CallLiveActivityActionHandler.perform(.toggleAudio, forRoomToken: roomToken)
        return .result()
    }
}

@available(iOS 17.0, *)
struct HangUpCallIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Leave call"
    static let isDiscoverable = false

    @Parameter(title: "Conversation token")
    var roomToken: String

    init() {}

    init(roomToken: String) {
        self.roomToken = roomToken
    }

    func perform() async throws -> some IntentResult {
        await CallLiveActivityActionHandler.perform(.hangUp, forRoomToken: roomToken)
        return .result()
    }
}
