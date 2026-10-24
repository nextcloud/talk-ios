//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import ImageIO
import SDWebImage

@objcMembers
public class FilePreviewImageView: UIImageView {

    public var currentRequest: SDWebImageCombinedOperation?

    private static let localPreviewCache = NSCache<NSString, UIImage>()

    // Detects reuse while a local preview loads
    private var localPreviewKey: NSString?

    public func setPreview(forFileId fileId: String, withWidth width: Int, withHeight height: Int, usingAccount account: TalkAccount) {
        self.cancelPreview()

        self.currentRequest = NCAPIController.sharedInstance().getPreviewForFile(fileId, width: width, height: height, forAccount: account, completionBlock: { [weak self] image, _ in
            guard let self, let image else { return }

            self.image = image
        })
    }

    /// Downscaled preview of a local file. Kept by the reference id of its message, so the message the server
    /// posts finds it as well, without the file. The completion only runs if the preview is still wanted.
    public func setLocalPreview(forReferenceId referenceId: String, fileURL: URL?, maximumPixelSize: Int, completion: ((UIImage?) -> Void)? = nil) {
        self.cancelPreview()

        let key = Self.localPreviewKey(forReferenceId: referenceId, maximumPixelSize: maximumPixelSize)
        self.localPreviewKey = key

        if let cachedImage = Self.localPreviewCache.object(forKey: key) {
            self.image = cachedImage

            // Async, so a completion updating the table view never runs inside cellForRowAt
            DispatchQueue.main.async { [weak self] in
                guard let self, self.localPreviewKey == key else { return }

                completion?(cachedImage)
            }

            return
        }

        guard let fileURL else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
            ] as CFDictionary

            var image: UIImage?

            if let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
               let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options) {
                image = UIImage(cgImage: thumbnail)
            }

            DispatchQueue.main.async {
                guard let self, self.localPreviewKey == key else { return }

                if let image {
                    Self.localPreviewCache.setObject(image, forKey: key)
                    self.image = image
                }

                completion?(image)
            }
        }
    }

    public static func hasLocalPreview(forReferenceId referenceId: String, maximumPixelSize: Int) -> Bool {
        return self.localPreviewCache.object(forKey: self.localPreviewKey(forReferenceId: referenceId, maximumPixelSize: maximumPixelSize)) != nil
    }

    private static func localPreviewKey(forReferenceId referenceId: String, maximumPixelSize: Int) -> NSString {
        return "\(referenceId)-\(maximumPixelSize)" as NSString
    }

    public func cancelPreview() {
        self.currentRequest?.cancel()
        self.currentRequest = nil
        self.localPreviewKey = nil
    }
}
