//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// Reasons for downloading a file of a conversation to fail.
///
/// Deliberately without user facing messages: how a failed download is reported depends on the
/// caller, which knows whether it can show an alert, fall back to a preview or nothing at all.
public enum ChatFileDownloadError: Error {

    /// The file could not be found on the server, or its metadata could not be read.
    case fileUnavailable(errorDescription: String)

    /// Downloading the file from the server failed.
    case downloadFailed(errorDescription: String)

    /// The download was cancelled by the caller.
    case cancelled
}
