//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import XCTest
@testable import NextcloudTalk

/// Which upload options the share confirmation offers for what is being shared.
final class UnitShareConfirmationOptionsTest: TestBaseRealm {

    private func shareConfirmationViewController(withConversationSubfolders conversationSubfolders: Bool) throws -> ShareConfirmationViewController {
        self.updateCapabilities { capabilities in
            capabilities.conversationSubfoldersEnabled = conversationSubfolders
        }

        let account = NCDatabaseManager.sharedInstance().activeAccount()
        // An unmanaged copy, as the view controller outlives the realm of the test otherwise
        let room = NCRoom(value: self.addRoom(withToken: "token", withName: "Room"))
        let capabilities = try XCTUnwrap(NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId))

        let viewController = try XCTUnwrap(ShareConfirmationViewController(room: room, thread: nil, account: account, serverCapabilities: capabilities))

        // Adding an item reloads the collection view, which needs the cell its view registers
        viewController.loadViewIfNeeded()

        return viewController
    }

    private func addImage(to viewController: ShareConfirmationViewController) throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }

        viewController.shareItemController.addItem(withImageDataAndName: try XCTUnwrap(image.pngData()), withName: "IMG_1.png")
    }

    private func addContact(to viewController: ShareConfirmationViewController) throws {
        // Contacts are marked as an image by the share item controller, as they have an image as
        // their preview, so the options have to look at the file itself
        viewController.shareItemController.addItem(withContactDataAndName: Data("BEGIN:VCARD\nEND:VCARD".utf8), withName: "Contact_1.vcf")
    }

    func testImageOffersBothOptions() throws {
        let viewController = try self.shareConfirmationViewController(withConversationSubfolders: true)
        try self.addImage(to: viewController)

        XCTAssertTrue(viewController.availableOptions.imageQuality)
        XCTAssertTrue(viewController.availableOptions.sharePermission)
    }

    func testContactOffersNoImageQuality() throws {
        let viewController = try self.shareConfirmationViewController(withConversationSubfolders: true)
        try self.addContact(to: viewController)

        XCTAssertFalse(viewController.availableOptions.imageQuality)
        XCTAssertTrue(viewController.availableOptions.sharePermission)
    }

    func testWithoutConversationSubfoldersThereIsNoSharePermission() throws {
        let viewController = try self.shareConfirmationViewController(withConversationSubfolders: false)
        try self.addImage(to: viewController)

        XCTAssertTrue(viewController.availableOptions.imageQuality)
        XCTAssertFalse(viewController.availableOptions.sharePermission)
    }

    func testSharedTextOffersNoOptionsAtAll() throws {
        let viewController = try self.shareConfirmationViewController(withConversationSubfolders: true)
        try self.addImage(to: viewController)

        viewController.shareText("Not a file")

        XCTAssertFalse(viewController.availableOptions.imageQuality)
        XCTAssertFalse(viewController.availableOptions.sharePermission)
    }

    // MARK: - Image quality

    /// A photo sized image, written as JPEG like the ones the photo library hands over.
    private func addPhoto(to viewController: ShareConfirmationViewController) throws -> ShareItem {
        viewController.shareItemController.addItem(withImageDataAndName: try XCTUnwrap(self.photo(CGSize(width: 2400, height: 1800)).jpegData(compressionQuality: 0.9)),
                                                  withName: "IMG_0001.jpg")

        return try XCTUnwrap(viewController.shareItemController.shareItems.last)
    }

    /// A photo sized image, gradients and shapes, so a lossy encoder has something to work with.
    private func photo(_ size: CGSize) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [UIColor.systemIndigo.cgColor, UIColor.systemPink.cgColor, UIColor.systemYellow.cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.5, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])

            for index in 0..<40 {
                UIColor(white: CGFloat(index % 10) / 10, alpha: 0.35).setFill()
                let side = size.width / CGFloat(index + 3)
                context.cgContext.fillEllipse(in: CGRect(x: CGFloat(index) * side / 2, y: CGFloat(index) * side / 3, width: side, height: side))
            }
        }
    }

    private func pixelSize(ofFileAt path: String) throws -> CGSize {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])

        return CGSize(width: try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int),
                      height: try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int))
    }

    private func fileSize(ofFileAt path: String) throws -> Int {
        return try XCTUnwrap(FileManager.default.attributesOfItem(atPath: path)[.size] as? Int)
    }

    @MainActor
    func testStandardQualityUploadsADownscaledCopy() async throws {
        let viewController = try self.shareConfirmationViewController(withConversationSubfolders: false)
        let item = try self.addPhoto(to: viewController)

        let uploads = await viewController.uploads(for: viewController.shareItemController.shareItems, quality: .standard)
        let upload = try XCTUnwrap(uploads.first)

        XCTAssertNotEqual(upload.localPath, item.filePath, "the original was uploaded instead of a compressed copy")

        let size = try self.pixelSize(ofFileAt: upload.localPath)
        XCTAssertEqual(max(size.width, size.height), CGFloat(ChatImageCompressor.maxPixelSize))
        XCTAssertLessThan(try self.fileSize(ofFileAt: upload.localPath), try self.fileSize(ofFileAt: item.filePath))

        // The original has to survive, so a failed upload can be tried again
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.filePath))
    }

    @MainActor
    func testOriginalQualityUploadsTheFileItself() async throws {
        let viewController = try self.shareConfirmationViewController(withConversationSubfolders: false)
        let item = try self.addPhoto(to: viewController)

        let uploads = await viewController.uploads(for: viewController.shareItemController.shareItems, quality: .original)
        let upload = try XCTUnwrap(uploads.first)

        XCTAssertEqual(upload.localPath, item.filePath)
        XCTAssertEqual(upload.fileName, item.fileName)

        let size = try self.pixelSize(ofFileAt: upload.localPath)
        XCTAssertEqual(size, CGSize(width: 2400, height: 1800))
    }

    @MainActor
    func testStandardQualityLeavesOtherFilesAlone() async throws {
        let viewController = try self.shareConfirmationViewController(withConversationSubfolders: false)
        try self.addContact(to: viewController)
        let item = try XCTUnwrap(viewController.shareItemController.shareItems.last)

        let uploads = await viewController.uploads(for: viewController.shareItemController.shareItems, quality: .standard)
        let upload = try XCTUnwrap(uploads.first)

        XCTAssertEqual(upload.localPath, item.filePath)
        XCTAssertEqual(upload.fileName, "Contact_1.vcf")
    }

    @MainActor
    func testOriginalQualityKeepsWhatTheCameraDelivered() async throws {
        let viewController = try self.shareConfirmationViewController(withConversationSubfolders: false)

        // A photo taken with the camera reaches the app as a bitmap, not as a file, so the share
        // item controller is what encodes it. That must not spend the quality the sender may ask for.
        let image = try self.photo(CGSize(width: 2400, height: 1800))
        viewController.shareItemController.addItem(with: image)
        let item = try XCTUnwrap(viewController.shareItemController.shareItems.last)

        let uploads = await viewController.uploads(for: viewController.shareItemController.shareItems, quality: .original)
        let upload = try XCTUnwrap(uploads.first)
        let uploaded = try self.fileSize(ofFileAt: upload.localPath)

        let lossless = try XCTUnwrap(image.jpegData(compressionQuality: 1)).count
        let lossy = try XCTUnwrap(image.jpegData(compressionQuality: 0.7)).count

        XCTAssertEqual(Double(uploaded), Double(lossless), accuracy: Double(lossless) * 0.05,
                       "the image was re-encoded before the sender could choose its quality")
        XCTAssertGreaterThan(uploaded, lossy)

        // Its dimensions are untouched either way
        XCTAssertEqual(try self.pixelSize(ofFileAt: upload.localPath), CGSize(width: 2400, height: 1800))
    }
}
