//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

extension NCChatMessage {

    var fileUploadReference: FileUploadReference? {
        return FileUploadReference(referenceId: self.referenceId)
    }

    var isGroupableFileMessage: Bool {
        return self.plainFileShare != nil && self.fileUploadReference != nil
    }

    var isFileCardMessage: Bool {
        guard let file = self.plainFileShare else { return false }

        return !file.isPreviewableMedia
    }

    /// The single file this message shares, if it shares one and nothing else.
    private var plainFileShare: NCMessageFileParameter? {
        // A comment excludes deleted messages, voice messages and call recordings by type alone
        guard !self.isSystemMessage, self.messageType == kMessageTypeComment else {
            return nil
        }

        // Failed and deleting messages keep their own bubble so their state stays visible, and an
        // edited one is shown separately, the same way message grouping treats it
        guard !self.sendingFailed, !self.isDeleting, self.lastEditTimestamp == 0 else {
            return nil
        }

        // `file()` returns nil when a message shares more than one, so this checks for exactly one.
        // A rich object - poll, location, deck card - is never part of a file share.
        guard let file = self.file(), self.messageParameters["object"] == nil else {
            return nil
        }

        // A contact card is drawn with the contact's photo, which a group cannot show
        return file.mimetype == "text/vcard" ? nil : file
    }

    /// Whether the message carries nothing but the placeholders of its file
    var sharesFileWithoutCaption: Bool {
        return self.message.wholeMatch(of: Self.filePlaceholders) != nil
    }

    private static let filePlaceholders = /\s*(\{file(-\d+)?\}\s*)*/
}
