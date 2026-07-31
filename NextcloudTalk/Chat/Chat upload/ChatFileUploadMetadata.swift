//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// The `talkMetaData` payload that is sent along when a file is announced to a conversation,
/// either through the attachment endpoint or through the files sharing API.
///
/// This is the single place where the wire format of those keys is defined.
struct ChatFileUploadMetadata {

    /// Message text sent together with the file. Requires the `media-caption` capability.
    var caption: String?

    /// Send the message without triggering a notification for the other participants.
    var silent = false

    /// Identifier of the thread the file belongs to.
    var threadId: Int?

    /// Identifier of the message this file replies to.
    var replyTo: Int?

    /// Token of the conversation the parent message lives in.
    /// Only set when it differs from the target conversation, which makes this a private reply.
    var replyToToken: String?

    /// Marks the file as a voice message, so it is rendered as a playable recording.
    var isVoiceMessage = false

    func asDictionary() -> [String: Any] {
        var metaData: [String: Any] = [:]

        if self.isVoiceMessage {
            metaData["messageType"] = kMessageTypeVoiceMessage
        }

        if let caption = self.caption?.trimmingCharacters(in: .whitespaces), !caption.isEmpty {
            metaData["caption"] = caption
        }

        if self.silent {
            metaData["silent"] = true
        }

        if let threadId = self.threadId {
            metaData["threadId"] = threadId
        }

        if let replyTo = self.replyTo {
            metaData["replyTo"] = replyTo
        }

        if let replyToToken = self.replyToToken {
            metaData["replyToToken"] = replyToToken
        }

        return metaData
    }
}
