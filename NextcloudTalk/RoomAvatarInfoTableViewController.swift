//
// Copyright (c) 2023 Marcel Müller <marcel.mueller@nextcloud.com>
//
// Author Marcel Müller <marcel.mueller@nextcloud.com>
//
// GNU GPL version 3 or any later version
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
import UIKit

@objcMembers class RoomAvatarInfoTableViewController: UITableViewController,
                                                        UINavigationControllerDelegate,
                                                        UIImagePickerControllerDelegate,
                                                        UITextFieldDelegate,
                                                        AvatarEditViewDelegate,
                                                        TOCropViewControllerDelegate {

    var room: NCRoom
    var imagePicker: UIImagePickerController?
    var headerView: AvatarEditView
    var rightBarButton = UIBarButtonItem()
    var modifyingView = UIActivityIndicatorView()

    init(room: NCRoom) {
        self.room = room
        self.headerView = AvatarEditView()

        super.init(nibName: "RoomAvatarInfoTableViewController", bundle: nil)

        self.headerView.delegate = self

        self.headerView.scopeButton.isHidden = true
        self.headerView.nameLabel.isHidden = true

        self.updateHeaderView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: NCAppBranding.themeTextColor()]
        self.navigationController?.navigationBar.tintColor = NCAppBranding.themeTextColor()
        self.navigationController?.navigationBar.barTintColor = NCAppBranding.themeColor()
        self.navigationController?.navigationBar.isTranslucent = false
        self.navigationItem.title = NSLocalizedString("Conversation details", comment: "")

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.titleTextAttributes = [.foregroundColor: NCAppBranding.themeTextColor()]
        appearance.backgroundColor = NCAppBranding.themeColor()
        self.navigationItem.standardAppearance = appearance
        self.navigationItem.compactAppearance = appearance
        self.navigationItem.scrollEdgeAppearance = appearance

        self.tableView.register(UINib(nibName: kTextInputTableViewCellNibName, bundle: nil), forCellReuseIdentifier: kTextInputCellIdentifier)
        self.tableView.tableHeaderView = self.headerView

        self.modifyingView.color = NCAppBranding.themeTextColor()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    func updateHeaderView() {
        self.headerView.avatarImageView.setAvatar(for: self.room, with: self.traitCollection.userInterfaceStyle)

        self.headerView.editView.isHidden = !NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityConversationAvatars, forAccountId: self.room.accountId)
        self.headerView.trashButton.isHidden = !self.room.isCustomAvatar

        // Need to have an explicit size here for the header view
        let size = self.headerView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        self.headerView.frame = CGRect(origin: .zero, size: size)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let textInputCell = tableView.dequeueReusableCell(withIdentifier: kTextInputCellIdentifier) as? TextInputTableViewCell ??
        TextInputTableViewCell(style: .default, reuseIdentifier: kTextInputCellIdentifier)

        textInputCell.textField.delegate = self
        textInputCell.textField.text = self.room.displayName

        return textInputCell
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return NSLocalizedString("Name", comment: "")
    }

    func updateRoomAndRemoveModifyingView() {
        NCRoomsManager.sharedInstance().updateRoom(self.room.token) { _, _ in
            self.room = NCRoomsManager.sharedInstance().room(withToken: self.room.token, forAccountId: self.room.accountId)

            self.updateHeaderView()
            self.tableView.reloadData()

            self.removeModifyingView()
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
            self.imagePicker?.sourceType = UIImagePickerController.SourceType.camera
            if self.imagePicker != nil {
                self.imagePicker!.delegate = self
                self.present(self.imagePicker!, animated: true)
            }
        }
    }

    func presentPhotoLibrary() {
        DispatchQueue.main.async {
            self.imagePicker = UIImagePickerController()
            self.imagePicker?.sourceType = .photoLibrary
            if self.imagePicker != nil {
                self.imagePicker!.delegate = self
                self.present(self.imagePicker!, animated: true)
            }
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

    func avatarEditViewRemoveAvatar(_ controller: AvatarEditView?) {
        self.showModifyingView()

        NCAPIController.sharedInstance().removeAvatar(for: room) { error in
            if error != nil {
                NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("An error occurred while removing the avatar", comment: ""), withMessage: nil)
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

        self.showModifyingView()

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCAPIController.sharedInstance().renameRoom(self.room.token, for: activeAccount, withName: newRoomValue) { error in
            if error != nil {
                let alertTitle = NSLocalizedString("Could not rename the conversation", comment: "")
                NCUserInterfaceController.sharedInstance().presentAlert(withTitle: alertTitle, withMessage: nil)
            }

            self.updateRoomAndRemoveModifyingView()
        }

        return true
    }
}
