//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

public class NCChatFileControllerWrapper: NSObject, NCChatFileControllerDelegate {
    typealias FileId = String
    typealias FileDownloadCompletionBlock = ((_ fileLocalPath: String?) -> Void)

    private var completionBlocks = [FileId: [FileDownloadCompletionBlock]]()
    private var fileControllers = [FileId: NCChatFileController]()

    static let shared = NCChatFileControllerWrapper()

    @MainActor
    public func downloadFile(withFileId fileId: String, completionBlock: @escaping (_ fileLocalPath: String?) -> Void) {
        if var existingBlocks = completionBlocks[fileId] {
            // We are already downloading this file, don't do it again, just ensure we call the completion block later on
            existingBlocks.append(completionBlock)
            completionBlocks[fileId] = existingBlocks

            return
        }

        completionBlocks[fileId, default: []].append(completionBlock)

        let fileController = NCChatFileController()
        fileController.delegate = self

        fileControllers[fileId] = fileController

        fileController.downloadFile(withFileId: fileId)
    }

    private func executeCompletionBlocks(forFileId fileId: String, withPath fileLocalPath: String?) {
        DispatchQueue.main.async { [self] in
            if let existingBlocks = completionBlocks[fileId] {
                for block in existingBlocks {
                    block(fileLocalPath)
                }

                completionBlocks.removeValue(forKey: fileId)
            }

            fileControllers.removeValue(forKey: fileId)
        }
    }

    public func fileControllerDidLoadFile(_ fileController: NCChatFileController, with fileStatus: NCChatFileStatus) {
        executeCompletionBlocks(forFileId: fileStatus.fileId, withPath: fileStatus.fileLocalPath)
    }

    public func fileControllerDidFailLoadingFile(_ fileController: NCChatFileController, withFileId fileId: String, withErrorDescription errorDescription: String) {
        executeCompletionBlocks(forFileId: fileId, withPath: nil)
    }

}
