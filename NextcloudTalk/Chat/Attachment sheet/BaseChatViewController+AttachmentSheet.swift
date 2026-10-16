//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

/// The "+" button of the chat opens the attachment sheet, see `AttachmentSheetViewController`.
extension BaseChatViewController: AttachmentSheetViewControllerDelegate {

    func presentAttachmentSheet() {
        // The keyboard will be hidden when an action is invoked. Depending on what
        // attachment is shared, not resigning might lead to a currupted chat view
        self.textView.resignFirstResponder()

        let actions = AttachmentSheetAction.availableActions(room: self.room, account: self.account, thread: self.thread)
        let sheet = AttachmentSheetViewController(actions: actions)
        sheet.delegate = self
        sheet.modalPresentationStyle = .pageSheet

        // The chat is not usable while the sheet is open, there is no undimmed detent
        if let sheetPresentationController = sheet.sheetPresentationController {
            sheetPresentationController.detents = [.medium(), .large()]
            sheetPresentationController.prefersGrabberVisible = true
            sheetPresentationController.prefersScrollingExpandsWhenScrolledToEdge = false
        }

        self.present(sheet, animated: true)
    }

    // MARK: - AttachmentSheetViewController delegate

    func attachmentSheet(_ sheet: AttachmentSheetViewController, didChoose action: AttachmentSheetAction) {
        sheet.dismiss(animated: true) { [weak self] in
            self?.handleAttachmentSheetAction(action)
        }
    }

    func attachmentSheet(_ sheet: AttachmentSheetViewController, didExport files: [AttachmentAssetExporter.ExportedFile]) {
        guard let (shareConfirmationVC, navigationController) = self.createShareConfirmationViewController() else {
            // Every file has a folder of its own
            for file in files {
                try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent())
            }

            sheet.dismiss(animated: true)
            return
        }

        shareConfirmationVC.setChatMessage(self.textView.text)
        self.setChatMessage("")

        sheet.dismiss(animated: true) {
            self.present(navigationController, animated: true) {
                for file in files {
                    shareConfirmationVC.shareItemController.addItem(withURLAndName: file.url, withName: file.fileName)
                }
            }
        }
    }

    private func handleAttachmentSheetAction(_ action: AttachmentSheetAction) {
        self.textView.resignFirstResponder()

        switch action {
        case .camera:
            self.checkAndPresentCamera()
        case .photoLibrary:
            self.presentPhotoLibrary()
        case .giphy:
            self.presentGiphyPicker()
        case .files:
            self.presentDocumentPicker()
        case .nextcloudFiles:
            self.presentNextcloudFilesBrowser()
        case .thread:
            self.presentThreadCreation()
        case .poll:
            self.presentPollCreation()
        case .location:
            self.presentShareLocation()
        case .contact:
            self.presentShareContact()
        }
    }
}
