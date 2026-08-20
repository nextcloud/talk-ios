//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import LinkPresentation
import UIKit

///
/// Shares the original file, waiting for it if it is not downloaded yet.
///
/// The share sheet opens right away and builds its activity list from the placeholder. Only once
/// the user picked a destination does UIKit ask for `item`, on a background thread, and shows its
/// own progress while we wait. That way the download runs while the user is still choosing.
///
class MediaShareItemProvider: UIActivityItemProvider {

    private let placeholderURL: URL
    private let thumbnail: UIImage?
    private let requestFile: (@escaping (URL?) -> Void) -> Void
    private let timeout: TimeInterval = 60

    private(set) var didFail = false

    init(placeholderURL: URL, thumbnail: UIImage?, requestFile: @escaping (@escaping (URL?) -> Void) -> Void) {
        self.placeholderURL = placeholderURL
        self.thumbnail = thumbnail
        self.requestFile = requestFile

        super.init(placeholderItem: placeholderURL)
    }

    ///
    /// The share sheet builds its header once, when it opens, and the file may not be downloaded at
    /// that point. So the picture the media viewer is showing is handed over instead.
    ///
    override func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = self.placeholderURL.lastPathComponent

        if let thumbnail = self.scaledThumbnail() {
            metadata.imageProvider = NSItemProvider(object: thumbnail)
        }

        return metadata
    }

    // The header is small and the image is handed to another process, so don't send a full sized one
    private func scaledThumbnail() -> UIImage? {
        guard let thumbnail, thumbnail.size.width > 0, thumbnail.size.height > 0 else { return nil }

        let scale = min(512 / thumbnail.size.width, 512 / thumbnail.size.height, 1)

        guard scale < 1 else { return thumbnail }

        return thumbnail.preparingThumbnail(of: .init(width: thumbnail.size.width * scale, height: thumbnail.size.height * scale))
    }

    override var item: Any {
        // UIKit calls this on a background thread. Waiting below would deadlock otherwise.
        guard !Thread.isMainThread else { return self.placeholderURL }

        var resolvedURL: URL?
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.main.async {
            self.requestFile { fileURL in
                resolvedURL = fileURL
                semaphore.signal()
            }
        }

        // Poll instead of waiting in one go, so dismissing the share sheet does not keep this
        // thread around until the timeout
        let deadline = Date().addingTimeInterval(self.timeout)

        while !self.isCancelled, Date() < deadline {
            if semaphore.wait(timeout: .now() + 0.1) == .success {
                break
            }
        }

        guard let resolvedURL else {
            self.didFail = !self.isCancelled

            // Nothing better to hand over. The activity fails, and the media viewer shows the error.
            return self.placeholderURL
        }

        return resolvedURL
    }
}
