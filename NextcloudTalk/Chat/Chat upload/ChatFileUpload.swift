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

    /// Reference id of the temporary message this upload belongs to, if there is one.
    var referenceId: String?
}
