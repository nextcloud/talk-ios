//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// One file that should be uploaded to the server and posted into a conversation.
struct ChatFileUpload {

    /// Path of the file on this device.
    let localPath: String

    /// Name the file should have in the conversation. Not necessarily the name of the local
    /// file, which can be a temporary one.
    let fileName: String

    let room: NCRoom

    let account: TalkAccount

    var metadata = ChatFileUploadMetadata()

    /// Reference id of the message this upload will become.
    ///
    /// Files shared in one go carry the same upload hash here, which is how the clients recognize
    /// them as one upload and show them as a single message. See `referenceId(uploadId:index:)`.
    var referenceId: String?

    /// Whether the other participants may modify the file, instead of only viewing it.
    ///
    /// Only honoured with conversation subfolders enabled: the server keeps updatable files in a
    /// separate subfolder, so this is a choice per upload and does not affect earlier ones.
    var allowUpdate = false
}

extension ChatFileUpload {

    /// Builds the reference id for one file of an upload, so that the clients can recognize the
    /// files shared together and show them as a single message. See `FileUploadReference`.
    ///
    /// - Parameter uploadId: Identifies one upload. The same value has to be passed for every file
    ///                       shared together, and a different one for the next upload.
    /// - Parameter index: Zero-based position of the file within the upload.
    static func referenceId(uploadId: String, index: Int) -> String? {
        return FileUploadReference(uploadId: uploadId, index: index)?.referenceId
    }
}
