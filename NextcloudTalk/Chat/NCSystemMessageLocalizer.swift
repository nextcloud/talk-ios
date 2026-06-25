//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// Client-side localization of system messages received via the external-signaling chat relay.
///
/// When messages are delivered over the chat relay instead of the chat API, the
/// payload's `message` field is not localized for the receiving user (chat relay sends a single
/// payload to every recipient). This recreates the localized template the chat API would have
/// returned, so the existing `parsedMessage` substitution path can render it unchanged.
///
/// This is a direct port of `tryLocalizeSystemMessage` from the  web app
/// (`src/utils/message.ts`); keep the source strings in sync with the web app so translations
/// are reused. A `nil` return signals the caller to fall back to fetching the message via chat API.
@objcMembers
public class NCSystemMessageLocalizer: NSObject {

    // Returns a localized system-message template (still containing {actor}/{user}/{poll}
    // placeholders for parsedMessage to substitute), or nil if the message must be fetched
    // from the chat API instead (e.g. call_ended, file/object shares, unknown types).
    // swiftlint:disable:next cyclomatic_complexity
    public static func localizedSystemMessage(for message: NCChatMessage, in room: NCRoom, account: TalkAccount, silentCall: Bool) -> String? {
        switch message.systemMessage ?? "" {

        // System messages that must be retrieved from the chat API.
        case "call_ended", "call_ended_everyone", "file_shared", "object_shared":
            return nil

        // System messages that don't need localization.
        case "reaction", "reaction_deleted", "reaction_revoked",
             "message_deleted", "message_edited", "thread_created", "thread_renamed":
            return message.message

        case "call_started":
            if silentCall {
                if message.isMessage(from: account.userId) {
                    return room.isOneToOne
                        ? NSLocalizedString("Outgoing silent call", comment: "")
                        : NSLocalizedString("You started a silent call", comment: "")
                } else {
                    return room.isOneToOne
                        ? NSLocalizedString("Incoming silent call", comment: "")
                        : NSLocalizedString("{actor} started a silent call", comment: "")
                }
            } else {
                if message.isMessage(from: account.userId) {
                    return room.isOneToOne
                        ? NSLocalizedString("Outgoing call", comment: "")
                        : NSLocalizedString("You started a call", comment: "")
                } else {
                    return room.isOneToOne
                        ? NSLocalizedString("Incoming call", comment: "")
                        : NSLocalizedString("{actor} started a call", comment: "")
                }
            }

        case "call_joined":
            return message.isMessage(from: account.userId)
                ? NSLocalizedString("You joined the call", comment: "")
                : NSLocalizedString("{actor} joined the call", comment: "")

        case "call_left":
            return message.isMessage(from: account.userId)
                ? NSLocalizedString("You left the call", comment: "")
                : NSLocalizedString("{actor} left the call", comment: "")

        case "moderator_promoted", "guest_moderator_promoted":
            if message.isMessage(from: account.userId) {
                return NSLocalizedString("You promoted {user} to moderator", comment: "")
            } else if message.userParameterRefersTo(account.userId) {
                return message.isFromCommandLine
                    ? NSLocalizedString("An administrator promoted you to moderator", comment: "")
                    : NSLocalizedString("{actor} promoted you to moderator", comment: "")
            }
            return message.isFromCommandLine
                ? NSLocalizedString("An administrator promoted {user} to moderator", comment: "")
                : NSLocalizedString("{actor} promoted {user} to moderator", comment: "")

        case "moderator_demoted", "guest_moderator_demoted":
            if message.isMessage(from: account.userId) {
                return NSLocalizedString("You demoted {user} from moderator", comment: "")
            } else if message.userParameterRefersTo(account.userId) {
                return message.isFromCommandLine
                    ? NSLocalizedString("An administrator demoted you from moderator", comment: "")
                    : NSLocalizedString("{actor} demoted you from moderator", comment: "")
            }
            return message.isFromCommandLine
                ? NSLocalizedString("An administrator demoted {user} from moderator", comment: "")
                : NSLocalizedString("{actor} demoted {user} from moderator", comment: "")

        case "history_cleared":
            return message.isMessage(from: account.userId)
                ? NSLocalizedString("You cleared the history of the conversation", comment: "")
                : NSLocalizedString("{actor} cleared the history of the conversation", comment: "")

        case "poll_voted":
            return NSLocalizedString("Someone voted on the poll {poll}", comment: "")

        case "poll_closed":
            return message.isMessage(from: account.userId)
                ? NSLocalizedString("You ended the poll {poll}", comment: "")
                : NSLocalizedString("{actor} ended the poll {poll}", comment: "")

        case "recording_started":
            return message.isMessage(from: account.userId)
                ? NSLocalizedString("You started the video recording", comment: "")
                : NSLocalizedString("{actor} started the video recording", comment: "")

        case "recording_stopped":
            return message.isMessage(from: account.userId)
                ? NSLocalizedString("You stopped the video recording", comment: "")
                : NSLocalizedString("{actor} stopped the video recording", comment: "")

        default:
            // Unknown system messages, fall back to the chat API.
            return nil
        }
    }
}
