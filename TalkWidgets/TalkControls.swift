//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AppIntents
import SwiftUI
import WidgetKit

// Controls for Control Center, the Lock Screen and the Action button (iOS 18 and later)

@available(iOS 18.0, *)
struct MuteMicrophoneControl: ControlWidget {

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }

        func currentValue() async throws -> Bool {
            let state = TalkControlsState.load(appGroupIdentifier: WidgetStorage.appGroupIdentifier)
            return state.isInCall && state.isMicrophoneMuted
        }
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: TalkControlsState.muteMicrophoneControlKind, provider: Provider()) { isMuted in
            ControlWidgetToggle(isOn: isMuted, action: ControlMuteMicrophoneIntent()) {
                Label(NSLocalizedString("Mute in call", comment: "Name of a control in Control Center"), systemImage: "mic.fill")
            } valueLabel: { isOn in
                Label(isOn ? NSLocalizedString("Muted", comment: "") : NSLocalizedString("Microphone on", comment: ""),
                      systemImage: isOn ? "mic.slash.fill" : "mic.fill")
            }
            .tint(.red)
        }
        .displayName(LocalizedStringResource("Mute in call"))
        .description(LocalizedStringResource("Mutes or unmutes your microphone in a Nextcloud Talk call."))
    }
}

@available(iOS 18.0, *)
struct DoNotDisturbControl: ControlWidget {

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }

        func currentValue() async throws -> Bool {
            return TalkControlsState.load(appGroupIdentifier: WidgetStorage.appGroupIdentifier).userStatus == "dnd"
        }
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: TalkControlsState.doNotDisturbControlKind, provider: Provider()) { isOn in
            ControlWidgetToggle(isOn: isOn, action: ControlDoNotDisturbIntent()) {
                Label(NSLocalizedString("Do not disturb", comment: "User status"), systemImage: "minus.circle.fill")
            } valueLabel: { isOn in
                Label(isOn ? NSLocalizedString("Do not disturb", comment: "User status") : NSLocalizedString("Online", comment: "User status"),
                      systemImage: isOn ? "minus.circle.fill" : "circle.fill")
            }
            .tint(.red)
        }
        .displayName(LocalizedStringResource("Talk: Do not disturb"))
        .description(LocalizedStringResource("Sets your Nextcloud status to Do not disturb, which mutes all notifications."))
    }
}

@available(iOS 18.0, *)
struct NewConversationControl: ControlWidget {

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: TalkControlsState.newConversationControlKind) {
            ControlWidgetButton(action: ControlNewConversationIntent()) {
                Label(NSLocalizedString("New conversation", comment: "Name of a control in Control Center"), systemImage: "plus.bubble.fill")
            }
        }
        .displayName(LocalizedStringResource("New conversation"))
        .description(LocalizedStringResource("Opens Nextcloud Talk to start a new conversation."))
    }
}
