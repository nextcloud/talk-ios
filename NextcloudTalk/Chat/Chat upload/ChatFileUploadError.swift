//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// Reasons for a file upload to a conversation to fail.
///
/// Deliberately without user facing messages: how a failed upload is reported depends on the
/// caller, which knows whether it can show an alert, a list of failed items or nothing at all.
enum ChatFileUploadError: Error {

    /// The place to upload the file to could not be determined.
    case destinationUnavailable(underlyingError: Error?)

    /// The attachment folder does not exist and could not be created.
    case attachmentFolderUnavailable

    /// Uploading the file to the server failed.
    case uploadFailed(errorCode: Int, errorDescription: String)

    /// The file was uploaded, but posting it into the conversation failed.
    case shareFailed(underlyingError: Error)

    /// There is not enough space left on the server for this file.
    case quotaExceeded

    /// The server asked us to slow down.
    case tooManyRequests
}
