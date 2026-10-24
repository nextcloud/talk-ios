//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// Follows the download of one file through the notifications NCChatFileController posts
class ChatFileDownloadObserver {

    enum Change {
        case isDownloading(Bool)
        /// nil while the size of the download is unknown
        case progress(Float?)
    }

    var fileParameter: NCMessageFileParameter?

    private let onChange: (Change) -> Void
    private var observers: [NSObjectProtocol] = []

    init(onChange: @escaping (Change) -> Void) {
        self.onChange = onChange

        // Download progress can be reported off the main queue
        self.observers.append(NotificationCenter.default.addObserver(forName: .NCChatFileControllerDidChangeIsDownloading, object: nil, queue: .main) { [weak self] notification in
            guard let status = self?.status(from: notification) else { return }

            self?.onChange(.isDownloading(status.isDownloading))
        })

        self.observers.append(NotificationCenter.default.addObserver(forName: .NCChatFileControllerDidChangeDownloadProgress, object: nil, queue: .main) { [weak self] notification in
            guard let status = self?.status(from: notification) else { return }

            self?.onChange(.progress(status.canReportProgress ? Float(status.downloadProgress) : nil))
        })
    }

    deinit {
        self.observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func status(from notification: Notification) -> NCChatFileStatus? {
        guard let fileParameter = self.fileParameter else { return nil }

        return NCChatFileStatus.getStatus(from: notification, for: fileParameter)
    }
}
