//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import UIKit
import SwiftUI

enum RoomAvatarInfoSection: Int {
    case kRoomNameSection = 0
    case kRoomDescriptionSection
}

@objcMembers class RoomAvatarInfoTableViewController: UITableViewController,
                                                      UINavigationControllerDelegate,
                                                      UIImagePickerControllerDelegate,
                                                      UITextFieldDelegate,
                                                      AvatarEditViewDelegate,
                                                      EmojiAvatarPickerViewControllerDelegate,
                                                      TextViewTableViewCellDelegate,
                                                      TOCropViewControllerDelegate {

    var room: NCRoom
    var imagePicker: UIImagePickerController?
    var headerView: AvatarEditView
    var rightBarButton = UIBarButtonItem()
    var modifyingView = UIActivityIndicatorView()
    var descriptionMaxLength = 500
    var descriptionHeaderView = HeaderWithButton()
    var currentDescription = ""

    init(room: NCRoom) {
        self.room = room
        self.headerView = AvatarEditView()

        super.init(nibName: "RoomAvatarInfoTableViewController", bundle: nil)

        self.headerView.delegate = self

        self.headerView.scopeButton.isHidden = true
        self.headerView.nameLabel.isHidden = true

        self.descriptionHeaderView.label.text = NSLocalizedString("Description", comment: "").uppercased()
        self.descriptionHeaderView.button.setTitle(NSLocalizedString("Save", comment: "Save conversation description"), for: .normal)
        self.descriptionHeaderView.button.addTarget(self, action: #selector(setButtonPressed), for: .touchUpInside)
        self.descriptionHeaderView.button.isHidden = true
        self.currentDescription = self.room.roomDescription

        self.updateHeaderView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NCAppBranding.styleViewController(self)

        self.navigationItem.title = NSLocalizedString("Conversation details", comment: "")

        self.tableView.register(TextFieldTableViewCell.self, forCellReuseIdentifier: TextFieldTableViewCell.identifier)
        self.tableView.register(TextViewTableViewCell.self, forCellReuseIdentifier: TextViewTableViewCell.identifier)
        self.tableView.tableHeaderView = self.headerView

        self.modifyingView.color = NCAppBranding.themeTextColor()

        if let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: self.room.accountId) {
            self.descriptionMaxLength = serverCapabilities.descriptionLength
        }
    }

    func updateHeaderView() {
        self.headerView.avatarImageView.setAvatar(for: self.room)

        self.headerView.editView.isHidden = !NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityConversationAvatars, forAccountId: self.room.accountId)
        self.headerView.trashButton.isHidden = !self.room.isCustomAvatar

        // Need to have an explicit size here for the header view
        let size = self.headerView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        self.headerView.frame = CGRect(origin: .zero, size: size)
    }

    func getAvatarInfoSections() -> [Int] {
        var sections = [Int]()

        // Room name section
        sections.append(RoomAvatarInfoSection.kRoomNameSection.rawValue)

        // Room description section
        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityRoomDescription, forAccountId: self.room.accountId) {
            sections.append(RoomAvatarInfoSection.kRoomDescriptionSection.rawValue)
        }

        return sections
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return self.getAvatarInfoSections().count
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if section == RoomAvatarInfoSection.kRoomDescriptionSection.rawValue {
            return descriptionHeaderView
        }

        return nil
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 40
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == RoomAvatarInfoSection.kRoomNameSection.rawValue {
            let textInputCell: TextFieldTableViewCell = tableView.dequeueOrCreateCell(withIdentifier: TextFieldTableViewCell.identifier)
            textInputCell.textField.delegate = self
            textInputCell.textField.text = self.room.displayName
            textInputCell.textField.isEnabled = !self.room.isEvent
            textInputCell.textField.alpha = self.room.isEvent ? 0.5 : 1
            return textInputCell
        } else if indexPath.section == RoomAvatarInfoSection.kRoomDescriptionSection.rawValue {
            let descriptionCell: TextViewTableViewCell = tableView.dequeueOrCreateCell(withIdentifier: TextViewTableViewCell.identifier)
            descriptionCell.textView.text = self.room.roomDescription
            descriptionCell.textView.isEditable = !self.room.isEvent
            descriptionCell.textView.alpha = self.room.isEvent ? 0.5 : 1
            descriptionCell.delegate = self
            descriptionCell.characterLimit = descriptionMaxLength
            descriptionCell.selectionStyle = .none
            return descriptionCell
        }

        return UITableViewCell()
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == RoomAvatarInfoSection.kRoomNameSection.rawValue {
            return NSLocalizedString("Name", comment: "")
        } else if section == RoomAvatarInfoSection.kRoomDescriptionSection.rawValue {
            return NSLocalizedString("Description", comment: "")
        }

        return nil
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard self.room.isEvent else { return nil }

        // Always add the footer to the last cell
        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityRoomDescription, forAccountId: self.room.accountId) {
            if section == RoomAvatarInfoSection.kRoomDescriptionSection.rawValue {
                return NSLocalizedString("This conversation is attached to a calendar event. Edit the event to change the name/description of the conversation.", comment: "")
            }
        } else if section == RoomAvatarInfoSection.kRoomNameSection.rawValue {
            return NSLocalizedString("This conversation is attached to a calendar event. Edit the event to change the name/description of the conversation.", comment: "")
        }

        return nil
    }

    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return UITableView.automaticDimension
    }

    func updateRoomAndRemoveModifyingView() {
        NCRoomsManager.sharedInstance().updateRoom(self.room.token) { _, _ in
            guard let room = NCDatabaseManager.sharedInstance().room(withToken: self.room.token, forAccountId: self.room.accountId) else { return }

            self.room = room
            self.currentDescription = self.room.roomDescription

            self.updateHeaderView()
            self.tableView.reloadData()

            self.removeModifyingView()
        }
    }

    func setButtonPressed() {
        guard let account = room.account else { return }

        self.showModifyingView()
        self.descriptionHeaderView.button.isHidden = true

        NCAPIController.sharedInstance().setRoomDescription(currentDescription, forRoom: room.token, forAccount: account) { error in
            if error != nil {
                NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("An error occurred while setting description", comment: ""), withMessage: nil)
            }

            self.updateRoomAndRemoveModifyingView()
        }
    }

    func showModifyingView() {
        modifyingView.startAnimating()
        self.headerView.changeButtonState(to: false)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: modifyingView)
        self.tableView.isUserInteractionEnabled = false
    }

    func removeModifyingView() {
        modifyingView.stopAnimating()
        self.headerView.changeButtonState(to: true)
        self.tableView.isUserInteractionEnabled = true
    }

    // MARK: - Present camera/photo library

    func checkAndPresentCamera() {
        // https://stackoverflow.com/a/20464727/2512312
        let mediaType: String = AVMediaType.video.rawValue
        let authStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType(mediaType))
        if authStatus == AVAuthorizationStatus.authorized {
            self.presentCamera()
            return
        } else if authStatus == AVAuthorizationStatus.notDetermined {
            AVCaptureDevice.requestAccess(for: AVMediaType(mediaType)) { granted in
                if granted {
                    self.presentCamera()
                }
            }
            return
        }

        let alertTitle = NSLocalizedString("Could not access camera", comment: "")
        let alertMessage = NSLocalizedString("Camera access is not allowed. Check your settings.", comment: "")
        NCUserInterfaceController.sharedInstance().presentAlert(withTitle: alertTitle, withMessage: alertMessage)
    }

    func presentCamera() {
        DispatchQueue.main.async {
            self.imagePicker = UIImagePickerController()
            if let imagePicker = self.imagePicker {
                imagePicker.sourceType = .camera
                imagePicker.delegate = self
                self.present(imagePicker, animated: true)
            }
        }
    }

    func presentPhotoLibrary() {
        DispatchQueue.main.async {
            self.imagePicker = UIImagePickerController()
            if let imagePicker = self.imagePicker {
                imagePicker.sourceType = .photoLibrary
                imagePicker.delegate = self
                self.present(imagePicker, animated: true)
            }
        }
    }

    func presentEmojiAvatarPicker() {
        DispatchQueue.main.async {
            let emojiAvatarPickerVC = EmojiAvatarPickerViewController()
            emojiAvatarPickerVC.delegate = self
            let emojiAvatarPickerNC = UINavigationController(rootViewController: emojiAvatarPickerVC)
            self.present(emojiAvatarPickerNC, animated: true, completion: nil)
        }
    }

    // MARK: - UIImagePickerController Delegate

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let mediaType = info[UIImagePickerController.InfoKey.mediaType] as? String
        if mediaType == "public.image" {
            let image = info[UIImagePickerController.InfoKey.originalImage] as? UIImage
            self.dismiss(animated: true) {
                if let image = image {
                    let cropViewController = TOCropViewController(croppingStyle: TOCropViewCroppingStyle.circular, image: image)
                    cropViewController.delegate = self
                    self.present(cropViewController, animated: true)
                }
            }
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        self.dismiss(animated: true, completion: nil)
    }

    // MARK: - TextViewTableViewCellDelegate

    func textViewCellTextViewDidChange(_ cell: TextViewTableViewCell) {
        DispatchQueue.main.async {
            self.tableView?.beginUpdates()
            self.tableView?.endUpdates()

            self.currentDescription = cell.textView.text ?? ""
            self.descriptionHeaderView.button.isHidden = self.currentDescription == self.room.roomDescription
        }
    }

    func textViewCellDidExceedCharacterLimit(_ cell: TextViewTableViewCell) {
        NotificationPresenter.shared().present(
            text: NSLocalizedString("Description cannot be longer than 500 characters", comment: ""),
            dismissAfterDelay: 3.0,
            includedStyle: .warning)
    }

    // MARK: - TOCROPViewControllerDelegate

    func cropViewController(_ cropViewController: TOCropViewController, didCropTo image: UIImage, with cropRect: CGRect, angle: Int) {
        // Fixes weird iOS 13 bug: https://github.com/TimOliver/TOCropViewController/issues/365
        cropViewController.transitioningDelegate = nil
        cropViewController.dismiss(animated: true) {
            // Need to dismiss cropViewController first before showing the activityIndicator
            self.showModifyingView()

            NCAPIController.sharedInstance().setAvatarFor(self.room, with: image) { error in
                if error != nil {
                    let errorDialog = UIAlertController(title: NSLocalizedString("An error occurred while setting the avatar", comment: ""), message: nil, preferredStyle: .alert)
                    let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil)
                    errorDialog.addAction(okAction)
                    self.present(errorDialog, animated: true, completion: nil)
                }

                self.updateRoomAndRemoveModifyingView()
            }
        }
    }

    func cropViewController(_ cropViewController: TOCropViewController, didFinishCancelled cancelled: Bool) {
        // Fixes weird iOS 13 bug: https://github.com/TimOliver/TOCropViewController/issues/365
        cropViewController.transitioningDelegate = nil
        cropViewController.dismiss(animated: true)
    }

    // MARK: - AvaterEditViewDelegate

    func avatarEditViewPresentCamera(_ controller: AvatarEditView?) {
        self.checkAndPresentCamera()
    }

    func avatarEditViewPresentPhotoLibrary(_ controller: AvatarEditView?) {
        self.presentPhotoLibrary()
    }

    func avatarEditViewPresentEmojiAvatarPicker(_ controller: AvatarEditView?) {
        self.presentEmojiAvatarPicker()
    }

    func avatarEditViewRemoveAvatar(_ controller: AvatarEditView?) {
        self.showModifyingView()

        NCAPIController.sharedInstance().removeAvatar(for: room) { error in
            if error != nil {
                NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("An error occurred while removing the avatar", comment: ""), withMessage: nil)
            }

            self.updateRoomAndRemoveModifyingView()
        }
    }

    // MARK: - EmojiAvatarPickerViewControllerDelegate

    func didSelectEmoji(emoji: NSString, color: NSString, image: UIImage) {
        self.showModifyingView()

        NCAPIController.sharedInstance().setEmojiAvatarFor(room, withEmoji: emoji as String, andColor: color as String) { error in
            if error != nil {
                let errorDialog = UIAlertController(title: NSLocalizedString("An error occurred while setting the avatar", comment: ""), message: nil, preferredStyle: .alert)
                let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil)
                errorDialog.addAction(okAction)
                self.present(errorDialog, animated: true, completion: nil)
            }

            self.updateRoomAndRemoveModifyingView()
        }
    }

    // MARK: - UITextField delegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()

        let newRoomValue = textField.text!.trimmingCharacters(in: CharacterSet.whitespaces)

        if newRoomValue == self.room.name {
            return true
        }

        if newRoomValue.isEmpty {
            let alertTitle = NSLocalizedString("Could not set conversation name", comment: "")
            let alertMessage = NSLocalizedString("Conversation name cannot be empty", comment: "")
            NCUserInterfaceController.sharedInstance().presentAlert(withTitle: alertTitle, withMessage: alertMessage)

            self.tableView.reloadData()

            return true
        }

        guard let account = room.account else { return true }

        self.showModifyingView()

        NCAPIController.sharedInstance().renameRoom(self.room.token, forAccount: account, withName: newRoomValue) { error in
            if error != nil {
                let alertTitle = NSLocalizedString("Could not rename the conversation", comment: "")
                NCUserInterfaceController.sharedInstance().presentAlert(withTitle: alertTitle, withMessage: nil)
            }

            self.updateRoomAndRemoveModifyingView()
        }

        return true
    }
}
