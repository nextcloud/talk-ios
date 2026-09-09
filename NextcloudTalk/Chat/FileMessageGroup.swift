//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// The files of one upload, shown as a single message instead of one message per file.
///
/// The server stores one message per shared file and knows nothing about this. Mirrors
/// `combineFileMessages.ts` of the web client, so that a conversation reads the same everywhere.
struct FileMessageGroup {

    /// The messages of the group, in the order they appear in the conversation. Never fewer than two.
    let messages: [NCChatMessage]

    /// The message the group is shown as.
    ///
    /// The last one, so that the timestamp, the read state and the message actions of the group are
    /// those of its newest message. A caption ends the group it belongs to, so the caption of an
    /// upload is always the text of this message.
    var anchor: NCChatMessage {
        // Groups are only ever built from two messages or more
        return self.messages[self.messages.count - 1]
    }

    /// The messages of the group in the order their files were shared in.
    ///
    /// Not necessarily the order the messages arrived in: a client that posts the files of an
    /// upload in parallel has them arrive in any order, and one that failed to upload a file in
    /// the middle leaves a gap.
    var messagesInUploadOrder: [NCChatMessage] {
        return self.messages.sorted { first, second in
            (first.fileUploadReference?.position ?? 0) < (second.fileUploadReference?.position ?? 0)
        }
    }

    /// Splits the messages of a conversation, in the order they are shown in, into the groups of
    /// files that were shared as one upload.
    ///
    /// A file shared on its own stays an ordinary message, so only runs of more than one message
    /// are returned. Anything that is not a plain file share of the same upload ends the run before
    /// it, and so does a reply to another message. A file shared with a caption ends the run it
    /// belongs to, because the caption is added to the file shared last.
    static func groups(in messages: [NCChatMessage]) -> [FileMessageGroup] {
        var groups: [FileMessageGroup] = []
        var run: [NCChatMessage] = []

        func endRun() {
            if run.count > 1 {
                groups.append(FileMessageGroup(messages: run))
            }

            run = []
        }

        for message in messages {
            guard message.isGroupableFileMessage else {
                endRun()
                continue
            }

            if let previous = run.last, !self.belongToTheSameUpload(message, previous) {
                endRun()
            }

            run.append(message)

            if !message.sharesFileWithoutCaption {
                endRun()
            }
        }

        endRun()

        return groups
    }

    /// Whether two file shares are part of the same upload, and reply to the same message.
    ///
    /// Their position within the upload is deliberately not compared: a file that failed to upload
    /// leaves a gap, and the files around it still belong together.
    private static func belongToTheSameUpload(_ message: NCChatMessage, _ other: NCChatMessage) -> Bool {
        return message.fileUploadReference?.uploadHash == other.fileUploadReference?.uploadHash
            && message.parentId == other.parentId
    }
}
