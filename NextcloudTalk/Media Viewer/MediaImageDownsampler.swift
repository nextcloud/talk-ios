//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import ImageIO
import UIKit
import os

// Decodes images from disk at a bounded size. Loading with UIImage(contentsOfFile:) and scaling
// afterwards needs the full resolution bitmap and the scaled one at the same time, which is what
// made the media viewer run out of memory on large pictures.
enum MediaImageDownsampler {

    private static let minimumPixelSize: CGFloat = 1024
    private static let maximumPixelSize: CGFloat = 4096

    // Must not be called on the main thread, the decode happens synchronously here
    static func decodeImage(at url: URL, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // ImageIO does not apply the EXIF orientation on its own, unlike UIImage(contentsOfFile:).
            // The server-side preview we replace is already rotated, so getting this wrong flips the image.
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Decode on this thread instead of lazily on first draw, which would be on the main thread
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        return UIImage(cgImage: cgImage)
    }

    // Enough pixels to stay sharp up to the given zoom, clamped to what we can afford to allocate
    static func recommendedPixelSize(forViewportSize viewportSize: CGSize, displayScale: CGFloat, zoomScale: CGFloat) -> CGFloat {
        let scale = displayScale > 0 ? displayScale : 2
        let longestEdge = max(viewportSize.width, viewportSize.height)
        let needed = longestEdge * scale * max(zoomScale, 1)

        return min(max(needed, minimumPixelSize), min(maximumPixelSize, affordablePixelSize()))
    }

    private static func affordablePixelSize() -> CGFloat {
        // Zero when there is no limit to report, e.g. inside an app extension
        let availableBytes = Double(os_proc_available_memory())

        guard availableBytes > 0 else { return maximumPixelSize }

        // Give a single image a quarter of the remaining headroom, assuming 4 bytes per pixel
        // and a square image as the worst case for a given longest edge.
        let edge = (availableBytes / 4 / 4).squareRoot()

        return max(CGFloat(edge), minimumPixelSize)
    }
}
