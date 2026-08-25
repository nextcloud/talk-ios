//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The quality an image is uploaded in, chosen by the user before sending.
enum ChatImageQuality {

    /// Downscale and re-encode the image, which is the default.
    case standard

    /// Upload the image as it is, without touching it.
    case original
}

/// Re-encodes images to a size that is reasonable to send into a conversation.
///
/// Kept deliberately close to the web client (max 1280 pixels, 80% quality) so the same image ends
/// up roughly the same size no matter where it was sent from. Unlike the web, which encodes WebP,
/// this produces JPEG: iOS can decode WebP but not encode it.
enum ChatImageCompressor {

    /// Longest edge of a compressed image in pixels, which matches HD resolution.
    static let maxPixelSize = 1280

    /// Encoding quality of a compressed image.
    static let compressionQuality = 0.8

    /// File extensions that are images, but are not worth re-encoding: an animation would lose all
    /// but its first frame and a vector would only lose its ability to scale.
    private static let excludedFileExtensions = ["gif", "svg", "svgz"]

    /// Whether an image of this type can be re-encoded.
    ///
    /// Based on the file name instead of `ShareItem.isImage`, which is also set for files that only
    /// have an image as their preview, like contacts.
    static func supportsCompression(fileName: String) -> Bool {
        let fileExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()

        guard !fileExtension.isEmpty, !self.excludedFileExtensions.contains(fileExtension) else { return false }

        return NCUtils.isImage(fileExtension: fileExtension)
    }

    /// Writes a downscaled copy of an image into `directory` and returns it.
    ///
    /// The original file is never touched, so it stays available for another attempt when uploading
    /// the compressed copy fails.
    ///
    /// - Returns: The compressed copy and the name it should have in the conversation, or `nil` when
    ///            the original should be uploaded instead, because compressing it did not help.
    nonisolated static func compressedCopy(of fileURL: URL, named fileName: String, in directory: URL) -> (url: URL, fileName: String)? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              CGImageSourceGetCount(source) > 0
        else { return nil }

        // Images that are already small enough are re-encoded as well, as an image can be heavy
        // without being large. Whether that paid off is decided on the result further down.
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Applies the orientation of the source, which the encoded copy does not carry anymore
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: self.maxPixelSize
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
        else { return nil }

        let compressedFileName = (fileName as NSString).deletingPathExtension + ".jpg"
        let compressedURL = self.uniqueURL(for: compressedFileName, in: directory)

        guard let destination = CGImageDestinationCreateWithURL(compressedURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }

        CGImageDestinationSetProperties(destination, [kCGImageDestinationLossyCompressionQuality: self.compressionQuality] as CFDictionary)
        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: compressedURL)
            return nil
        }

        // Re-encoding can make a file bigger, in which case the original is the better upload
        guard self.fileSize(of: compressedURL) < self.fileSize(of: fileURL) else {
            try? FileManager.default.removeItem(at: compressedURL)
            return nil
        }

        return (compressedURL, compressedFileName)
    }

    /// Directory the compressed copies of one send operation are written to.
    ///
    /// Emptied on every call, as the copies of a previous send are not needed anymore: a failed
    /// upload is retried from the original file.
    static func temporaryDirectory() -> URL? {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("upload-compressed", isDirectory: true)
        let fileManager = FileManager.default

        try? fileManager.removeItem(at: directory)

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            NCLog.log("Could not create the directory for compressed images: \(error.localizedDescription)")
            return nil
        }

        return directory
    }

    // MARK: - Utils

    private static func uniqueURL(for fileName: String, in directory: URL) -> URL {
        let fileURL = directory.appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return fileURL }

        let fileExtension = (fileName as NSString).pathExtension
        let nameWithoutExtension = (fileName as NSString).deletingPathExtension

        return directory.appendingPathComponent("\(nameWithoutExtension)-\(UUID().uuidString).\(fileExtension)")
    }

    private static func fileSize(of fileURL: URL) -> Int {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path) else { return 0 }

        return attributes[.size] as? Int ?? 0
    }
}
