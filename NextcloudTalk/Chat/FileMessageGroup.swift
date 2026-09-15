//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

struct FileMessageGroup {

    /// A file drawn the same way without belonging to an upload is a group of one.
    let messages: [NCChatMessage]

    /// The last message, so the group carries the newest timestamp and read state. A caption ends
    /// its group, so the caption of an upload is always the text of this message.
    var anchor: NCChatMessage {
        return self.messages[self.messages.count - 1]
    }

    /// Whether the group continues a block from the same author, and so shows no avatar or name.
    ///
    /// Follows the first message: the group is shown as its last one, which is always a continuation.
    var continuesAuthorBlock: Bool {
        return self.messages[0].isGroupMessage
    }

    /// Not the order the messages arrived in: files of one upload can be posted in parallel.
    var messagesInUploadOrder: [NCChatMessage] {
        return self.messages.sorted { first, second in
            (first.fileUploadReference?.position ?? 0) < (second.fileUploadReference?.position ?? 0)
        }
    }

    /// Splits the messages of a conversation, in the order they are shown, into the groups of files
    /// that were shared as one upload. Anything that is not a file of the same upload ends a group.
    static func groups(in messages: [NCChatMessage]) -> [FileMessageGroup] {
        var groups: [FileMessageGroup] = []
        var currentGroup: [NCChatMessage] = []

        /// Closes the group being collected. A single file is an ordinary message, not a group.
        func finishCurrentGroup() {
            if currentGroup.count > 1 {
                groups.append(FileMessageGroup(messages: currentGroup))
            }

            currentGroup = []
        }

        for message in messages {
            guard message.isGroupableFileMessage else {
                finishCurrentGroup()
                continue
            }

            if let previous = currentGroup.last, !self.belongToTheSameUpload(message, previous) {
                finishCurrentGroup()
            }

            currentGroup.append(message)

            // The caption is added to the file shared last, so it closes its group
            if !message.sharesFileWithoutCaption {
                finishCurrentGroup()
            }
        }

        finishCurrentGroup()

        return groups
    }

    /// Position within the upload is deliberately not compared: a file that failed to upload leaves
    /// a gap, and the files around it still belong together.
    private static func belongToTheSameUpload(_ message: NCChatMessage, _ other: NCChatMessage) -> Bool {
        return message.fileUploadReference?.uploadHash == other.fileUploadReference?.uploadHash
            && message.parentId == other.parentId
    }
}
