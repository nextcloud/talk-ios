//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// Downloads files of conversations, sharing one download between all callers asking for the same file.
///
/// Does not offer cancellation on purpose: the download is shared, so one caller losing interest
/// must not stop it for the others.
public class ChatFileDownloader: NSObject {
    typealias FileId = String

    private var completionHandlers = [FileId: [NCChatFileController.CompletionHandler]]()
    private var fileControllers = [FileId: NCChatFileController]()

    static let shared = ChatFileDownloader()

    @MainActor
    public func downloadFile(withFileId fileId: String, fromAccount account: TalkAccount, completionHandler: @escaping NCChatFileController.CompletionHandler) {
        completionHandlers[fileId, default: []].append(completionHandler)

        // We are already downloading this file, don't do it again, the handler above is called once it finishes
        guard fileControllers[fileId] == nil else { return }

        let fileController = NCChatFileController(account: account)
        fileControllers[fileId] = fileController

        fileController.downloadFile(withFileId: fileId) { [weak self] result in
            self?.executeCompletionHandlers(forFileId: fileId, with: result)
        }
    }

    private func executeCompletionHandlers(forFileId fileId: String, with result: Result<NCChatFileStatus, ChatFileDownloadError>) {
        DispatchQueue.main.async { [self] in
            fileControllers.removeValue(forKey: fileId)

            guard let handlers = completionHandlers.removeValue(forKey: fileId) else { return }

            for handler in handlers {
                handler(result)
            }
        }
    }
}
