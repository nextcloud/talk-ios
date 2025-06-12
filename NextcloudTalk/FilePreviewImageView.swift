//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SDWebImage

@objcMembers
public class FilePreviewImageView: UIImageView {

    public var currentRequest: SDWebImageCombinedOperation?

    public func setPreview(forFileId fileId: String, withWidth width: Int, withHeight height: Int, usingAccount account: TalkAccount) {
        self.currentRequest?.cancel()

        self.currentRequest = NCAPIController.sharedInstance().getPreviewForFile(fileId, width: width, height: height, using: account, withCompletionBlock: { [weak self] image, _, _ in
            guard let self, let image else { return }

            self.image = image
        })
    }

}
