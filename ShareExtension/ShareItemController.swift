//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

@objc public protocol ShareItemControllerDelegate: AnyObject {
    func shareItemControllerItemsChanged(_ shareItemController: ShareItemController)
}

@objcMembers public class ShareItemController: NSObject {

    // A photo just taken, a pasted image or a cropped one reaches the app as a bitmap, so it has to
    // be encoded here. The sender picks the quality later on, so nothing is thrown away yet.
    private static let imageQuality: CGFloat = 1.0

    public weak var delegate: ShareItemControllerDelegate?

    public var shareItems: [ShareItem] {
        return internalShareItems
    }

    private var internalShareItems: [ShareItem] = []
    private let tempDirectoryURL: URL

    public override init() {
        let fileManager = FileManager.default
        let tempDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("upload", isDirectory: true)

        if !fileManager.fileExists(atPath: tempDirectoryURL.path) {
            // Make sure our upload directory exists
            try? fileManager.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        } else {
            // Clean up any temporary files from a previous upload
            let previousFiles = (try? fileManager.contentsOfDirectory(atPath: tempDirectoryURL.path)) ?? []
            for previousFile in previousFiles {
                try? fileManager.removeItem(at: tempDirectoryURL.appendingPathComponent(previousFile))
            }
        }

        self.tempDirectoryURL = tempDirectoryURL

        super.init()
    }

    private func getFileLocalURL(_ fileName: String) -> URL {
        var fileLocalURL = tempDirectoryURL.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: fileLocalURL.path) {
            let extensionString = (fileName as NSString).pathExtension
            let nameWithoutExtension = (fileName as NSString).deletingPathExtension
            let newFileName = String(format: "%@%.f.%@", nameWithoutExtension, Date().timeIntervalSince1970 * 1000, extensionString)
            fileLocalURL = tempDirectoryURL.appendingPathComponent(newFileName)
        }

        return fileLocalURL
    }

    private func prepareFileForUploading(at fileURL: URL, to fileLocalURL: URL, withCoordinatorOption options: NSFileCoordinator.ReadingOptions) -> Bool {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var transferError: Error?

        // Make a local copy to prevent bug where file is removed after some time from inbox
        // See: https://stackoverflow.com/a/48007752/2512312
        coordinator.coordinate(readingItemAt: fileURL, options: options, error: &coordinationError) { newURL in
            if FileManager.default.fileExists(atPath: fileLocalURL.path) {
                try? FileManager.default.removeItem(at: fileLocalURL)
            }

            do {
                if options.contains(.forUploading) {
                    // newURL is a temporary snapshot that the coordinator unlinks after this block, so we take it over
                    try FileManager.default.moveItem(at: newURL, to: fileLocalURL)
                } else {
                    // newURL is the original file, which does not belong to us and must stay in place
                    try FileManager.default.copyItem(at: newURL, to: fileLocalURL)
                }
            } catch {
                transferError = error
            }
        }

        if let transferError {
            NSLog("Failed to transfer file for sharing: %@", transferError.localizedDescription)
        }

        return coordinationError == nil && transferError == nil
    }

    @objc(addItemWithURL:)
    public func addItem(with fileURL: URL) {
        addItem(withURLAndName: fileURL, withName: fileURL.lastPathComponent)
    }

    @objc(addItemWithURLAndName:withName:)
    public func addItem(withURLAndName fileURL: URL, withName fileName: String) {
        let fileLocalURL = getFileLocalURL(fileName)

        // NSFileCoordinatorReadingWithoutChanges is the fallback for files that can't be read for uploading
        guard prepareFileForUploading(at: fileURL, to: fileLocalURL, withCoordinatorOption: .forUploading) ||
              prepareFileForUploading(at: fileURL, to: fileLocalURL, withCoordinatorOption: .withoutChanges)
        else {
            NSLog("Failed to prepare file for sharing")
            return
        }

        NSLog("Adding shareItem: %@ %@", fileName, fileLocalURL.path)

        // Try to determine if the item is an image file
        // This can happen when sharing an image from the native ios files app
        let fileIsImage = NCUtils.isImage(fileExtension: fileLocalURL.pathExtension)
        let item = ShareItem(url: fileLocalURL, name: fileName, placeholderImage: getPlaceholderImage(for: fileLocalURL), isImage: fileIsImage)
        internalShareItems.append(item)
        delegate?.shareItemControllerItemsChanged(self)
    }

    @objc(addItemWithImage:)
    public func addItem(with image: UIImage) {
        let imageName = String(format: "IMG_%.f.jpg", Date().timeIntervalSince1970 * 1000)
        addItem(withImageAndName: image, withName: imageName)
    }

    @objc(addItemWithImageAndName:withName:)
    public func addItem(withImageAndName image: UIImage, withName imageName: String) {
        guard let jpegData = image.jpegData(compressionQuality: ShareItemController.imageQuality) else {
            NSLog("Failed to encode image for sharing: %@", imageName)
            return
        }

        addItem(withImageDataAndName: jpegData, withName: imageName)
    }

    @objc(addItemWithImageDataAndName:withName:)
    public func addItem(withImageDataAndName data: Data, withName imageName: String) {
        let fileLocalURL = getFileLocalURL(imageName)
        try? data.write(to: fileLocalURL, options: .atomic)

        NSLog("Adding shareItem with image: %@ %@", imageName, fileLocalURL.path)

        let item = ShareItem(url: fileLocalURL, name: imageName, placeholderImage: getPlaceholderImage(for: fileLocalURL), isImage: true)
        internalShareItems.append(item)
        delegate?.shareItemControllerItemsChanged(self)
    }

    @objc(getImageFromItem:)
    public func getImageFrom(_ item: ShareItem?) -> UIImage? {
        guard let item, item.fileURL != nil else { return nil }

        return UIImage(contentsOfFile: item.filePath)
    }

    @objc(addItemWithContactData:)
    public func addItem(withContactData data: Data) {
        let vCardFileName = String(format: "Contact_%.f.vcf", Date().timeIntervalSince1970 * 1000)
        addItem(withContactDataAndName: data, withName: vCardFileName)
    }

    @objc(addItemWithContactDataAndName:withName:)
    public func addItem(withContactDataAndName data: Data, withName vCardFileName: String) {
        let fileLocalURL = getFileLocalURL(vCardFileName)
        try? data.write(to: fileLocalURL, options: .atomic)

        NSLog("Adding shareItem with contact: %@ %@", vCardFileName, fileLocalURL.path)

        let item = ShareItem(url: fileLocalURL, name: vCardFileName, placeholderImage: getPlaceholderImage(for: fileLocalURL), isImage: true)
        internalShareItems.append(item)
        delegate?.shareItemControllerItemsChanged(self)
    }

    // Called when an item was edited in QuickLook and we want to use the edited file
    @objc(updateItem:withURL:)
    public func update(_ item: ShareItem, with fileURL: URL) {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?

        coordinator.coordinate(readingItemAt: fileURL, options: .forUploading, error: &coordinationError) { newURL in
            // Replace atomically: the original is only removed after the edited file was moved in
            do {
                _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: item.filePath), withItemAt: newURL)
            } catch {
                NSLog("Failed to replace shareItem with edited file: %@ %@", item.fileName ?? "", error.localizedDescription)
            }
        }

        if let coordinationError {
            NSLog("Failed to coordinate reading edited file: %@ %@", item.fileName ?? "", coordinationError.localizedDescription)
        }

        NSLog("Updating shareItem: %@ %@", item.fileName ?? "", item.filePath ?? "")
        delegate?.shareItemControllerItemsChanged(self)
    }

    @objc(updateItem:withImage:)
    public func update(_ item: ShareItem, with image: UIImage) {
        try? image.jpegData(compressionQuality: ShareItemController.imageQuality)?.write(to: URL(fileURLWithPath: item.filePath), options: .atomic)

        NSLog("Updating shareItem with Image: %@ %@", item.fileName ?? "", item.filePath ?? "")
        delegate?.shareItemControllerItemsChanged(self)
    }

    @objc(removeItem:)
    public func remove(_ item: ShareItem) {
        remove([item])
    }

    @objc(removeItems:)
    public func remove(_ items: [ShareItem]) {
        for item in items {
            cleanup(item)
            NSLog("Removing shareItem: %@ %@", item.fileName ?? "", item.filePath ?? "")
            internalShareItems.removeAll { $0 === item }
        }

        delegate?.shareItemControllerItemsChanged(self)
    }

    private func cleanup(_ item: ShareItem) {
        if FileManager.default.fileExists(atPath: item.filePath) {
            try? FileManager.default.removeItem(atPath: item.filePath)
        }
    }

    public func removeAllItems() {
        internalShareItems.forEach { cleanup($0) }
        internalShareItems.removeAll()
    }

    private func getPlaceholderImage(for fileURL: URL) -> UIImage? {
        return UIImage(named: NCUtils.previewImage(forFileExtension: fileURL.pathExtension))
    }
}
