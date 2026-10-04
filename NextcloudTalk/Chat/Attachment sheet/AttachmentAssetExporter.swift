//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import ImageIO
import Photos
import UniformTypeIdentifiers

/// Writes photos and videos of the photo library into files, so they can be handed to the upload confirmation.
///
/// The original resource of an asset is written, not a rendition: an animated GIF stays a GIF, a PNG stays a PNG
/// and a video stays a MOV. Edits made in the Photos app are kept by using the edited resource.
/// HEIC and HEIF photos are the exception, they are written as JPEG, as the server does not make previews of them.
enum AttachmentAssetExporter {

    struct ExportedFile {
        let url: URL
        let fileName: String
    }

    enum ExportError: LocalizedError {
        case noResource(fileName: String)
        case failed(fileName: String, underlyingError: Error)

        var errorDescription: String? {
            switch self {
            case .noResource(let fileName):
                return String(format: NSLocalizedString("“%@” could not be read from the photo library", comment: "File name"), fileName)
            case .failed(let fileName, let underlyingError):
                return String(format: NSLocalizedString("“%1$@” could not be prepared: %2$@", comment: "File name, error description"),
                              fileName, underlyingError.localizedDescription)
            }
        }
    }

    /// Where all exports are written to. Every export gets a folder of its own below it.
    static var exportsDirectory: URL {
        return FileManager.default.temporaryDirectory.appendingPathComponent("AttachmentSheet", isDirectory: true)
    }

    /// Creates the folder for the files of one send.
    static func makeExportDirectory() throws -> URL {
        let directory = self.exportsDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Removes exports of earlier sends. Files younger than `age` are kept, as an upload might still read them.
    static func removeOldExports(olderThan age: TimeInterval = 24 * 60 * 60) {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.creationDateKey]

        guard let folders = try? fileManager.contentsOfDirectory(at: self.exportsDirectory, includingPropertiesForKeys: keys) else { return }

        for folder in folders {
            let created = (try? folder.resourceValues(forKeys: Set(keys)))?.creationDate ?? .distantPast

            if Date().timeIntervalSince(created) > age {
                try? fileManager.removeItem(at: folder)
            }
        }
    }

    // MARK: - Naming and resource choice

    /// The edited resource of an asset if it has one, otherwise the original.
    static func preferredResource(in resources: [PHAssetResource], isVideo: Bool) -> PHAssetResource? {
        let types: [PHAssetResourceType] = isVideo ? [.fullSizeVideo, .video] : [.fullSizePhoto, .photo]

        for type in types {
            if let resource = resources.first(where: { $0.type == type }) {
                return resource
            }
        }

        return nil
    }

    /// The name of the file in the conversation: the name the asset was created with (like `IMG_0042`), and the
    /// type of the data that is exported. Both can differ, for example when a HEIC photo was edited.
    static func exportFileName(originalFileName: String, resourceFileName: String, uniformTypeIdentifier: String?, isVideo: Bool) -> String {
        let baseName = (originalFileName as NSString).deletingPathExtension
        var fileExtension = (resourceFileName as NSString).pathExtension

        if fileExtension.isEmpty, let uniformTypeIdentifier, let type = UTType(uniformTypeIdentifier) {
            fileExtension = type.preferredFilenameExtension ?? ""
        }

        if fileExtension.isEmpty {
            fileExtension = (originalFileName as NSString).pathExtension
        }

        if fileExtension.isEmpty {
            fileExtension = isVideo ? "mov" : "jpg"
        }

        var name = baseName

        if name.isEmpty {
            name = "\(isVideo ? "VID" : "IMG")_\(Int(Date().timeIntervalSince1970 * 1000))"
        }

        return "\(name).\(fileExtension)"
    }

    /// Whether a photo of this type is converted to JPEG, which is the case for HEIC and HEIF
    static func needsJPEGConversion(uniformTypeIdentifier: String?) -> Bool {
        guard let uniformTypeIdentifier, let type = UTType(uniformTypeIdentifier) else { return false }

        return type.conforms(to: .heic) || type.conforms(to: .heif)
    }

    /// The name of a file with the extension changed to jpg
    static func jpegFileName(for fileName: String) -> String {
        return (fileName as NSString).deletingPathExtension + ".jpg"
    }

    /// Writes a JPEG of an image file. Orientation and metadata of the image are kept.
    static func writeJPEG(from sourceURL: URL, to destinationURL: URL) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileReadCorruptFile) }

        CGImageDestinationAddImageFromSource(destination, source, 0, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    // MARK: - Export

    /// Writes the data of an asset into a new file below `directory`. Assets that live in iCloud are downloaded.
    ///
    /// - Parameter progress: Called on the main queue with the fraction of the download that is done
    /// - Throws: `ExportError`, when the data could not be read or written
    static func export(_ asset: PHAsset, into directory: URL, progress: ((Double) -> Void)? = nil) async throws -> ExportedFile {
        let isVideo = asset.mediaType == .video
        let resources = PHAssetResource.assetResources(for: asset)
        let originalType: PHAssetResourceType = isVideo ? .video : .photo
        let originalResource = resources.first(where: { $0.type == originalType })
        let displayName = originalResource?.originalFilename ?? resources.first?.originalFilename ?? asset.localIdentifier

        guard let resource = self.preferredResource(in: resources, isVideo: isVideo) else {
            throw ExportError.noResource(fileName: displayName)
        }

        let resourceFileName = self.exportFileName(originalFileName: originalResource?.originalFilename ?? resource.originalFilename,
                                                   resourceFileName: resource.originalFilename,
                                                   uniformTypeIdentifier: resource.uniformTypeIdentifier,
                                                   isVideo: isVideo)

        let convertsToJPEG = !isVideo && self.needsJPEGConversion(uniformTypeIdentifier: resource.uniformTypeIdentifier)
        let fileName = convertsToJPEG ? self.jpegFileName(for: resourceFileName) : resourceFileName

        // A folder per asset, as two assets can have the same file name
        let assetDirectory = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: assetDirectory, withIntermediateDirectories: true)
        let fileURL = assetDirectory.appendingPathComponent(fileName)

        // The data is written as it is, and converted afterwards when needed
        let writtenURL = convertsToJPEG ? assetDirectory.appendingPathComponent("source-" + resourceFileName) : fileURL

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        if let progress {
            options.progressHandler = { fraction in
                DispatchQueue.main.async { progress(fraction) }
            }
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHAssetResourceManager.default().writeData(for: resource, toFile: writtenURL, options: options) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }

            if convertsToJPEG {
                try self.writeJPEG(from: writtenURL, to: fileURL)
                try? FileManager.default.removeItem(at: writtenURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: assetDirectory)
            throw ExportError.failed(fileName: fileName, underlyingError: error)
        }

        return ExportedFile(url: fileURL, fileName: fileName)
    }
}
