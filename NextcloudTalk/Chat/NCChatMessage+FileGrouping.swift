//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

extension NCChatMessage {

    /// The upload the file of this message was shared as part of, when its reference id follows the
    /// format the clients agreed on. Nil for everything shared before that, which is then shown as
    /// a message of its own.
    var fileUploadReference: FileUploadReference? {
        return FileUploadReference(referenceId: self.referenceId)
    }

    /// Whether this message shares a file that may be shown together with the other files of its
    /// upload, instead of as a message of its own.
    ///
    /// Mirrors what the other clients group, so that a conversation reads the same everywhere:
    /// anything rendered by a widget of its own stays on its own, and so does a message that
    /// shares more than a single file.
    ///
    /// Note that a file shared with a caption is groupable as well. The caption ends the group it
    /// belongs to, but that is a property of the group, not of the message.
    var isGroupableFileMessage: Bool {
        // A message that failed to send, or is being deleted, keeps its own bubble so that its
        // state stays visible. Voice messages are excluded by the message type below.
        guard !self.isSystemMessage, !self.isDeletedMessage, !self.sendingFailed, !self.isDeleting else {
            return false
        }

        // An edited message is shown separately, the same way message grouping treats it
        guard self.messageType == kMessageTypeComment, self.lastEditTimestamp == 0 else {
            return false
        }

        // `file()` returns nil when a message shares more than one file, so this is also the check
        // for the message sharing exactly one
        guard let file = self.file(), let mimetype = file.mimetype else {
            return false
        }

        guard !self.isObjectShare, self.poll == nil, self.geoLocation() == nil, self.deckCard() == nil else {
            return false
        }

        // A contact card is drawn with the photo of the contact, which a group has nowhere to show.
        // Audio files are excluded on web because it renders a player for them, this client does
        // not: it shows them with the ordinary file cell, so they group like any other file.
        guard mimetype != "text/vcard" else {
            return false
        }

        return self.fileUploadReference != nil
    }

    /// Whether the message carries nothing but the placeholder of its file, which is what a file
    /// shared without a caption looks like.
    var sharesFileWithoutCaption: Bool {
        let text = self.message.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return true }
        guard text.hasPrefix("{file"), text.hasSuffix("}") else { return false }

        // Either '{file}' or '{file-1}', depending on how many files the sender put in the message
        let position = text.dropFirst("{file".count).dropLast()

        return position.isEmpty || (position.hasPrefix("-") && position.count > 1 && position.dropFirst().allSatisfy(\.isNumber))
    }
}
