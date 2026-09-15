//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

extension NCMessageFileParameter {

    /// Only media the server can render a preview of. Files (even with a preview) will be shown in the file list for now.
    var isPreviewableMedia: Bool {
        guard let mimetype = self.mimetype, self.previewAvailable else { return false }

        return NCUtils.isImage(fileType: mimetype) || NCUtils.isVideo(fileType: mimetype)
    }

    /// The extension and the size of the file, as shown next to its name in a group.
    var shortDescription: String {
        let fileExtension = (self.name as NSString?)?.pathExtension.uppercased() ?? ""
        let size = self.size ?? 0
        let formattedSize = size > 0 ? ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) : ""

        return [fileExtension, formattedSize].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
