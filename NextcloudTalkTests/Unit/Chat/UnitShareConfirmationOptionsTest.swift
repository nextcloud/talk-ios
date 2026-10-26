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

    // MARK: - Forwarding a file

    private func fileMessage(permissions: String?, accountId: String? = TestBaseRealm.fakeAccountId) -> NCChatMessage {
        let permissionsEntry = permissions.map { "\"permissions\": \"\($0)\"," } ?? ""
        let message = NCChatMessage()
        message.message = "{file}"
        message.accountId = accountId
        message.messageParametersJSONString = """
        { "file": { "type": "file", "id": "6160", "name": "a.jpg", \(permissionsEntry) "path": "Talk/a.jpg" } }
        """

        return message
    }

    /// The screen of a forwarded file, the real one but for the two requests it would make
    private func forwardingViewController(of message: NCChatMessage, delegate: ForwardDelegate) throws -> ForwardRecordingViewController {
        self.updateCapabilities { _ in }

        let account = NCDatabaseManager.sharedInstance().activeAccount()
        let room = NCRoom(value: self.addRoom(withToken: UUID().uuidString, withName: "Room"))
        let capabilities = try XCTUnwrap(NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId))
        let viewController = try XCTUnwrap(ForwardRecordingViewController(room: room, thread: nil, account: account, serverCapabilities: capabilities))

        viewController.loadViewIfNeeded()
        viewController.delegate = delegate
        viewController.forwardingMessage = true
        viewController.shareFileMessage(message)
        self.waitForMainQueue()

        return viewController
    }

    /// Lets what the screen did on the main queue run
    private func waitForMainQueue() {
        let done = expectation(description: "main queue")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    func testFileWithoutRightToShareIsForwardedAsCopy() throws {
        let delegate = ForwardDelegate()
        // Read and update only, e.g. a file shared without reshare
        let viewController = try self.forwardingViewController(of: self.fileMessage(permissions: "3"), delegate: delegate)

        viewController.sendCurrent(silently: false)

        XCTAssertEqual(viewController.copiedFileIds, ["6160"])
        XCTAssertEqual(viewController.sharedPaths, [])
    }

    func testFileWithRightToShareIsShared() throws {
        let delegate = ForwardDelegate()
        let viewController = try self.forwardingViewController(of: self.fileMessage(permissions: "27"), delegate: delegate)

        viewController.sendCurrent(silently: false)

        XCTAssertEqual(viewController.sharedPaths, ["Talk/a.jpg"])
        XCTAssertEqual(viewController.copiedFileIds, [])
    }

    func testFileWithoutPermissionsFromServerIsShared() throws {
        let delegate = ForwardDelegate()
        let viewController = try self.forwardingViewController(of: self.fileMessage(permissions: nil), delegate: delegate)

        viewController.sendCurrent(silently: false)

        XCTAssertEqual(viewController.sharedPaths, ["Talk/a.jpg"])
        XCTAssertEqual(viewController.copiedFileIds, [])
    }

    func testSilentSendIsKeptForTheCopy() throws {
        let delegate = ForwardDelegate()
        let viewController = try self.forwardingViewController(of: self.fileMessage(permissions: "3"), delegate: delegate)

        viewController.sendCurrent(silently: true)

        XCTAssertEqual(viewController.copiedMetaData?.silent, true)
    }

    func testFileOfAnotherAccountIsNeitherSharedNorCopied() throws {
        // Messages of the shared items have no account until the screen that opens them sets it
        for accountId in [nil, "otherAccountId"] as [String?] {
            let delegate = ForwardDelegate()
            let viewController = try self.forwardingViewController(of: self.fileMessage(permissions: "3", accountId: accountId), delegate: delegate)

            viewController.sendCurrent(silently: false)

            XCTAssertEqual(viewController.copiedFileIds, [])
            XCTAssertEqual(viewController.sharedPaths, [])
            XCTAssertEqual(delegate.failCount, 1)
        }
    }

    func testSecondTapDuringSendDoesNotSendAgain() throws {
        for permissions in ["3", "27"] {
            let delegate = ForwardDelegate()
            let viewController = try self.forwardingViewController(of: self.fileMessage(permissions: permissions), delegate: delegate)

            XCTAssertFalse(viewController.isSending)

            // The button, the button of the keyboard and the silent send
            viewController.sendButtonPressed()
            viewController.didPressRightButton(nil)
            viewController.silentSendPressed()

            XCTAssertTrue(viewController.isSending)
            XCTAssertEqual(viewController.sharedPaths.count + viewController.copiedFileIds.count, 1, "permissions \(permissions)")
            // The silent send came last and was ignored: the first one counts
            XCTAssertNotEqual(viewController.copiedMetaData?.silent, true)
        }
    }

    func testFailedSendCanBeRepeated() throws {
        let delegate = ForwardDelegate()
        let viewController = try self.forwardingViewController(of: self.fileMessage(permissions: "3"), delegate: delegate)

        viewController.sendCurrent(silently: false)
        XCTAssertEqual(viewController.copiedFileIds.count, 1)

        // Every end of a send, failed or not, stops the indicator
        viewController.stopAnimatingSharingIndicator()
        self.waitForMainQueue()
        XCTAssertFalse(viewController.isSending)

        viewController.sendCurrent(silently: true)
        XCTAssertEqual(viewController.copiedFileIds.count, 2)
        XCTAssertEqual(viewController.copiedMetaData?.silent, true)
    }

    func testRefusedSendCanBeRepeated() throws {
        // Another account: the send ends at once with a failure
        let delegate = ForwardDelegate()
        let viewController = try self.forwardingViewController(of: self.fileMessage(permissions: "3", accountId: nil), delegate: delegate)

        viewController.sendCurrent(silently: false)
        self.waitForMainQueue()
        XCTAssertFalse(viewController.isSending)

        viewController.sendCurrent(silently: false)
        XCTAssertEqual(delegate.failCount, 2)
    }

    func testScreenCannotBeLeftWhileSending() throws {
        let delegate = ForwardDelegate()
        let viewController = try self.forwardingViewController(of: self.fileMessage(permissions: "3"), delegate: delegate)

        XCTAssertFalse(viewController.navigationItem.hidesBackButton)
        XCTAssertFalse(viewController.isModalInPresentation)

        viewController.sendCurrent(silently: false)

        XCTAssertTrue(viewController.navigationItem.hidesBackButton)
        XCTAssertTrue(viewController.isModalInPresentation)

        viewController.stopAnimatingSharingIndicator()
        self.waitForMainQueue()

        XCTAssertFalse(viewController.navigationItem.hidesBackButton)
        XCTAssertFalse(viewController.isModalInPresentation)
    }

    func testCopyWithoutFileIdFailsAndCanBeRepeated() throws {
        // The real forwardCopy, only the share is replaced
        self.updateCapabilities { _ in }

        let account = NCDatabaseManager.sharedInstance().activeAccount()
        let room = NCRoom(value: self.addRoom(withToken: UUID().uuidString, withName: "Room"))
        let capabilities = try XCTUnwrap(NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId))
        let viewController = try XCTUnwrap(ShareConfirmationViewController(room: room, thread: nil, account: account, serverCapabilities: capabilities))
        let delegate = ForwardDelegate()

        viewController.loadViewIfNeeded()
        viewController.delegate = delegate

        let message = self.fileMessage(permissions: "3")
        message.messageParametersJSONString = """
        { "file": { "type": "file", "name": "a.jpg", "permissions": "3", "path": "Talk/a.jpg" } }
        """
        viewController.shareFileMessage(message)
        self.waitForMainQueue()

        viewController.sendCurrent(silently: false)
        self.waitForMainQueue()

        XCTAssertEqual(delegate.failCount, 1)
        XCTAssertFalse(viewController.isSending)
    }

    func testForwardMethod() {
        XCTAssertEqual(ShareConfirmationViewController.forwardMethod(canBeShared: true), .share)
        XCTAssertEqual(ShareConfirmationViewController.forwardMethod(canBeShared: false), .copy)
    }
}

/// The screen of a forwarded file without its requests: records what it would share or copy
private final class ForwardRecordingViewController: ShareConfirmationViewController {
    var sharedPaths: [String] = []
    var copiedFileIds: [String] = []
    var copiedMetaData: ChatFileUploadMetadata?

    override func shareFile(atPath path: String, canShare: Bool, metaData: ChatFileUploadMetadata) {
        self.sharedPaths.append(path)
    }

    override func forwardCopy(ofFileWithId fileId: String, metaData: ChatFileUploadMetadata) {
        self.copiedFileIds.append(fileId)
        self.copiedMetaData = metaData
    }
}

private final class ForwardDelegate: NSObject, ShareConfirmationViewControllerDelegate {
    var failCount = 0

    func shareConfirmationViewControllerDidFail(_ viewController: ShareConfirmationViewController) {
        self.failCount += 1
    }

    func shareConfirmationViewControllerDidFinish(_ viewController: ShareConfirmationViewController) {}
    func shareConfirmationViewControllerDidCancel(_ viewController: ShareConfirmationViewController) {}
}
