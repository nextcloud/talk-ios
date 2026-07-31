//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// Where a file is uploaded to, and therefore how it is posted into the conversation afterwards.
///
/// Which one of both is used depends on whether the server has conversation subfolders enabled.
enum ChatFileUploadDestination {

    /// The file is uploaded into the draft folder of the conversation subfolder, from where the
    /// attachment endpoint moves it into place and posts it.
    case draftFolder(draftPath: String, serverPath: String, serverURL: String)

    /// The file is uploaded into the attachment folder of the user and is afterwards shared into
    /// the conversation using the files sharing API.
    case attachmentFolder(serverPath: String, serverURL: String)

    /// Absolute URL the file is uploaded to.
    var serverURL: String {
        switch self {
        case .draftFolder(_, _, let serverURL): return serverURL
        case .attachmentFolder(_, let serverURL): return serverURL
        }
    }

    /// Path of the uploaded file, relative to the files root of the user.
    var serverPath: String {
        switch self {
        case .draftFolder(_, let serverPath, _): return serverPath
        case .attachmentFolder(let serverPath, _): return serverPath
        }
    }
}
