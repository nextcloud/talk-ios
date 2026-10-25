//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AppIntents

// Actions of the Control Center controls and of the buttons in the widgets.
// This file is part of the app and of the widget extension: the widget extension needs the types to show
// the controls and buttons, but has no access to the server. As LiveActivityIntents, they're performed in
// the app's process, which is launched in the background if needed (see TalkWidgetActions in the app).

@available(iOS 17.0, *)
struct WidgetMarkAsReadIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark conversation as read"
    static var isDiscoverable = false

    @Parameter(title: "Server")
    var server: String

    @Parameter(title: "User")
    var userId: String

    @Parameter(title: "Conversation")
    var token: String

    init() {}

    init(server: String, userId: String, token: String) {
        self.server = server
        self.userId = userId
        self.token = token
    }

    func perform() async throws -> some IntentResult {
        #if !APP_EXTENSION
        try await TalkWidgetActions.markConversationAsRead(server: server, userId: userId, token: token)
        #endif
        return .result()
    }
}

@available(iOS 17.0, *)
struct WidgetSetStatusIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Set status"
    static var isDiscoverable = false

    // online, away, dnd or invisible
    @Parameter(title: "Status")
    var status: String

    init() {}

    init(status: String) {
        self.status = status
    }

    func perform() async throws -> some IntentResult {
        #if !APP_EXTENSION
        try await TalkWidgetActions.setUserStatus(status)
        #endif
        return .result()
    }
}

@available(iOS 18.0, *)
struct ControlMuteMicrophoneIntent: SetValueIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Mute microphone in call"
    static var isDiscoverable = false

    @Parameter(title: "Muted")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        #if !APP_EXTENSION
        await TalkWidgetActions.setMicrophoneMuted(value)
        #endif
        return .result()
    }
}

@available(iOS 18.0, *)
struct ControlDoNotDisturbIntent: SetValueIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Do not disturb"
    static var isDiscoverable = false

    @Parameter(title: "Do not disturb")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        #if !APP_EXTENSION
        try await TalkWidgetActions.setUserStatus(value ? "dnd" : "online")
        #endif
        return .result()
    }
}

@available(iOS 18.0, *)
struct ControlNewConversationIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "New conversation"
    static var isDiscoverable = false
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        #if !APP_EXTENSION
        await TalkWidgetActions.presentNewConversation()
        #endif
        return .result()
    }
}
