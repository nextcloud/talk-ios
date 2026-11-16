//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import ActivityKit
import SwiftUI
import WidgetKit

struct CallLiveActivityWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CallActivityAttributes.self) { context in
            CallLiveActivityBanner(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    CallAvatarView(avatarPath: context.state.avatarPath, size: 44)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.roomName)
                            .font(.headline)
                            .lineLimit(1)
                        CallStatusText(attributes: context.attributes, state: context.state)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CallDurationText(state: context.state)
                        .font(.headline)
                        .foregroundStyle(.green)
                        .frame(maxWidth: 64, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        ToggleAudioButton(roomToken: context.attributes.roomToken, isAudioMuted: context.state.isAudioMuted, isWide: true)
                        HangUpButton(roomToken: context.attributes.roomToken, isWide: true)
                    }
                    .padding(.top, 8)
                }
            } compactLeading: {
                CallStateIcon(attributes: context.attributes, state: context.state)
            } compactTrailing: {
                CallDurationText(state: context.state)
                    .foregroundStyle(.green)
                    .frame(maxWidth: 48)
            } minimal: {
                CallStateIcon(attributes: context.attributes, state: context.state)
            }
            .keylineTint(.green)
        }
    }
}

struct CallLiveActivityBanner: View {
    let attributes: CallActivityAttributes
    let state: CallActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            CallAvatarView(avatarPath: state.avatarPath, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(attributes.roomName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: attributes.isVideoCall ? "video.fill" : "phone.fill")
                    CallStatusText(attributes: attributes, state: state)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))

                CallDurationText(state: state, alignment: .leading)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }

            Spacer(minLength: 0)

            ToggleAudioButton(roomToken: attributes.roomToken, isAudioMuted: state.isAudioMuted, isWide: false)
            HangUpButton(roomToken: attributes.roomToken, isWide: false)
        }
        .padding(16)
    }
}

struct CallAvatarView: View {
    let avatarPath: String?
    let size: CGFloat

    var body: some View {
        if let avatarPath, let image = UIImage(contentsOfFile: avatarPath) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.2.fill")
                .font(.system(size: size * 0.4))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.gray))
        }
    }
}

struct CallStateIcon: View {
    let attributes: CallActivityAttributes
    let state: CallActivityAttributes.ContentState

    var body: some View {
        if state.isAudioMuted {
            Image(systemName: "mic.slash.fill")
                .foregroundStyle(.orange)
        } else {
            Image(systemName: attributes.isVideoCall ? "video.fill" : "phone.fill")
                .foregroundStyle(.green)
        }
    }
}

struct CallStatusText: View {
    let attributes: CallActivityAttributes
    let state: CallActivityAttributes.ContentState

    var body: some View {
        switch state.status {
        case .connecting:
            Text(NSLocalizedString("Connecting to the call …", comment: ""))
        case .waitingForParticipants:
            Text(NSLocalizedString("Waiting for others to join call …", comment: ""))
        case .reconnecting:
            Text(NSLocalizedString("Reconnecting …", comment: "The connection to a call was lost and is being restored"))
        case .inCall:
            if let participantCount = state.participantCount {
                Text(String.localizedStringWithFormat(NSLocalizedString("%ld participants", comment: ""), participantCount))
            } else if attributes.isVideoCall {
                Text(NSLocalizedString("Video call", comment: ""))
            } else {
                Text(NSLocalizedString("Voice call", comment: "A call without video"))
            }
        }
    }
}

struct CallDurationText: View {
    let state: CallActivityAttributes.ContentState
    var alignment: TextAlignment = .trailing

    var body: some View {
        if state.status == .inCall, let callStartDate = state.callStartDate {
            // A timer text always takes all available width, so its alignment decides where the digits end up
            Text(timerInterval: callStartDate...Date.distantFuture, countsDown: false)
                .monospacedDigit()
                .multilineTextAlignment(alignment)
        } else {
            Text(verbatim: "…")
        }
    }
}

struct ToggleAudioButton: View {
    let roomToken: String
    let isAudioMuted: Bool
    let isWide: Bool

    var body: some View {
        Button(intent: ToggleCallAudioIntent(roomToken: roomToken)) {
            Image(systemName: isAudioMuted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isAudioMuted ? .black : .white)
                .frame(maxWidth: isWide ? .infinity : 44, minHeight: 44)
                .background(Capsule().fill(isAudioMuted ? Color.white : Color.white.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isAudioMuted ? NSLocalizedString("Microphone disabled", comment: "") : NSLocalizedString("Microphone enabled", comment: ""))
    }
}

struct HangUpButton: View {
    let roomToken: String
    let isWide: Bool

    var body: some View {
        Button(intent: HangUpCallIntent(roomToken: roomToken)) {
            Image(systemName: "phone.down.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: isWide ? .infinity : 44, minHeight: 44)
                .background(Capsule().fill(Color.red))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString("Leave call", comment: ""))
    }
}
