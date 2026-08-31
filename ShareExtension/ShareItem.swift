//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

@objcMembers public class ShareItem: NSObject {

    // Kept as implicitly unwrapped optionals to match the unannotated ObjC declarations these replace
    public var fileURL: URL!
    public var filePath: String!
    public var fileName: String!
    public var placeholderImage: UIImage!
    public var uploadProgress: CGFloat = 0
    public var isImage: Bool = false
    public var caption: String!

    @objc(initWithURL:name:placeholderImage:isImage:)
    public init(url fileURL: URL, name fileName: String, placeholderImage: UIImage?, isImage: Bool) {
        self.fileURL = fileURL
        self.filePath = fileURL.path
        self.fileName = fileName
        self.placeholderImage = placeholderImage
        self.uploadProgress = 0
        self.isImage = isImage
        self.caption = ""

        super.init()
    }
}
