//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

public class NCChatFileControllerWrapper: NSObject, NCChatFileControllerDelegate {

    let fileController = NCChatFileController()
    var completionBlock: ((_ fileLocalPath: String?) -> Void)?

    public func downloadFile(withFileId fileId: String, completionBlock: @escaping (_ fileLocalPath: String?) -> Void) {
        self.completionBlock = completionBlock

        fileController.delegate = self
        fileController.downloadFile(withFileId: fileId)
    }

    public func fileControllerDidLoadFile(_ fileController: NCChatFileController, with fileStatus: NCChatFileStatus) {
        self.completionBlock?(fileStatus.fileLocalPath)
    }

    public func fileControllerDidFailLoadingFile(_ fileController: NCChatFileController, withErrorDescription errorDescription: String) {
        self.completionBlock?(nil)
    }

}
