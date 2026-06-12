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

    /// System message types that can be handled client-side when received via the chat relay.
    private static let relayableTypes: Set<String> = [
        "call_started", "call_joined", "call_left", "call_ended", "call_ended_everyone",
        "thread_created", "thread_renamed", "message_deleted", "message_edited",
        "moderator_promoted", "moderator_demoted", "guest_moderator_promoted", "guest_moderator_demoted",
        "file_shared", "object_shared", "history_cleared", "poll_voted", "poll_closed",
        "recording_started", "recording_stopped"
    ]

    /// System message types whose original (server-sent) text needs no localization.
    private static let untranslatedTypes: Set<String> = [
        "reaction", "reaction_deleted", "reaction_revoked",
        "message_deleted", "message_edited", "thread_created", "thread_renamed"
    ]

    // Returns a localized system-message template (still containing {actor}/{user}/{poll}
    // placeholders for parsedMessage to substitute), or nil if the message must be fetched
    // from the chat API instead (e.g. call_ended, file/object shares, unknown types).
    // swiftlint:disable:next cyclomatic_complexity
    public static func localizedSystemMessage(for message: NCChatMessage, in room: NCRoom, account: TalkAccount, silentCall: Bool) -> String? {
        let systemMessage = message.systemMessage ?? ""

        if untranslatedTypes.contains(systemMessage) {
            // Keep the original message, it does not need localization.
            return message.message
        }

        if !relayableTypes.contains(systemMessage) {
            // Not a chat-relay-supported system message, fall back to the chat API.
            return nil
        }

        switch systemMessage {
        case "call_started":
            if silentCall {
                if selfIsActor(message, account) {
                    return room.isOneToOne
                        ? NSLocalizedString("Outgoing silent call", comment: "")
                        : NSLocalizedString("You started a silent call", comment: "")
                } else {
                    return room.isOneToOne
                        ? NSLocalizedString("Incoming silent call", comment: "")
                        : NSLocalizedString("{actor} started a silent call", comment: "")
                }
            } else {
                if selfIsActor(message, account) {
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
            return selfIsActor(message, account)
                ? NSLocalizedString("You joined the call", comment: "")
                : NSLocalizedString("{actor} joined the call", comment: "")

        case "call_left":
            return selfIsActor(message, account)
                ? NSLocalizedString("You left the call", comment: "")
                : NSLocalizedString("{actor} left the call", comment: "")

        case "call_ended", "call_ended_everyone":
            // Requires server-side computation (guests count, duration), fall back to the chat API.
            return nil

        case "moderator_promoted", "guest_moderator_promoted":
            if selfIsActor(message, account) {
                return NSLocalizedString("You promoted {user} to moderator", comment: "")
            } else if selfIsUser(message, account) {
                return cliIsActor(message)
                    ? NSLocalizedString("An administrator promoted you to moderator", comment: "")
                    : NSLocalizedString("{actor} promoted you to moderator", comment: "")
            }
            return cliIsActor(message)
                ? NSLocalizedString("An administrator promoted {user} to moderator", comment: "")
                : NSLocalizedString("{actor} promoted {user} to moderator", comment: "")

        case "moderator_demoted", "guest_moderator_demoted":
            if selfIsActor(message, account) {
                return NSLocalizedString("You demoted {user} from moderator", comment: "")
            } else if selfIsUser(message, account) {
                return cliIsActor(message)
                    ? NSLocalizedString("An administrator demoted you from moderator", comment: "")
                    : NSLocalizedString("{actor} demoted you from moderator", comment: "")
            }
            return cliIsActor(message)
                ? NSLocalizedString("An administrator demoted {user} from moderator", comment: "")
                : NSLocalizedString("{actor} demoted {user} from moderator", comment: "")

        case "file_shared", "object_shared":
            // Backend transforms these to normal chat messages, they should not be relayed as
            // system messages. Fall back to the chat API to get the authoritative message.
            return nil

        case "history_cleared":
            return selfIsActor(message, account)
                ? NSLocalizedString("You cleared the history of the conversation", comment: "")
                : NSLocalizedString("{actor} cleared the history of the conversation", comment: "")

        case "poll_voted":
            return NSLocalizedString("Someone voted on the poll {poll}", comment: "")

        case "poll_closed":
            return selfIsActor(message, account)
                ? NSLocalizedString("You ended the poll {poll}", comment: "")
                : NSLocalizedString("{actor} ended the poll {poll}", comment: "")

        case "recording_started":
            return selfIsActor(message, account)
                ? NSLocalizedString("You started the video recording", comment: "")
                : NSLocalizedString("{actor} started the video recording", comment: "")

        case "recording_stopped":
            return selfIsActor(message, account)
                ? NSLocalizedString("You stopped the video recording", comment: "")
                : NSLocalizedString("{actor} stopped the video recording", comment: "")

        default:
            // Not localizable client-side, fall back to the chat API.
            return nil
        }
    }

    // MARK: - Helpers

    // The message's actor is the local user. iOS accounts always authenticate as a regular user,
    // so this matches the web's selfIsActor for the only actor type we can be.
    private static func selfIsActor(_ message: NCChatMessage, _ account: TalkAccount) -> Bool {
        return message.isMessage(from: account.userId)
    }

    // The "user" parameter (the target of a moderator promotion/demotion) is the local user.
    private static func selfIsUser(_ message: NCChatMessage, _ account: TalkAccount) -> Bool {
        guard let userParameter = NCMessageParameter(dictionary: message.messageParameters["user"] as? [String: Any]) else {
            return false
        }
        return userParameter.type == "user" && userParameter.parameterId == account.userId
    }

    private static func cliIsActor(_ message: NCChatMessage) -> Bool {
        return message.actorId == "cli" && message.actorType == "guests"
    }
}
