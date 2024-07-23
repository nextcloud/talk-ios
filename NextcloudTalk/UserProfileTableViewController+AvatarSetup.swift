//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

extension UserProfileTableViewController {

    func avatarHeaderView() -> UIView? {
        let headerView = AvatarEditView()
        headerView.delegate = self

        headerView.avatarImageView?.image = NCAPIController.sharedInstance().userProfileImage(for: account, with: self.traitCollection.userInterfaceStyle)

        headerView.nameLabel?.text = account.userDisplayName
        headerView.nameLabel?.isHidden = self.isEditable

        let avatarScopeImage = self.imageForScope(scope: account.avatarScope)?.applyingSymbolConfiguration(iconHeaderConfiguration)
        headerView.scopeButton?.tag = kAvatarScopeButtonTag
        headerView.scopeButton?.setImage(avatarScopeImage, for: .normal)
        headerView.scopeButton?.addTarget(self, action: #selector(showScopeSelectionDialog(_:)), for: .touchUpInside)
        headerView.scopeButton?.isHidden = !(isEditable && showScopes)

        headerView.editView?.isHidden = !(isEditable && NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityTempUserAvatarAPI, forAccountId: account.accountId))

        // Avatar emojis are not allowed for now
        headerView.emojiButton.isHidden = true
        // Removal is only allowed for custom avatars
        headerView.trashButton.isHidden = !account.hasCustomAvatar

        // Need to have an explicit size here for the header view
        let size = headerView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        headerView.frame = CGRect(origin: .zero, size: size)
        return headerView
    }

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
        let alert = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: .alert)
        let okButton = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil)
        alert.addAction(okButton)
        NCUserInterfaceController.sharedInstance().presentAlertViewController(alert)
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

    func sendUserProfileImage(image: UIImage) {
        NCAPIController.sharedInstance().setUserProfileImage(image, for: account) { error, _ in
            if error == nil {
                self.refreshUserProfile()
            } else {
                self.showProfileImageError(NSLocalizedString("An error occurred setting profile image", comment: ""))
                print("Error removing profile image: \(error.debugDescription)")
            }
        }
    }

    func removeUserProfileImage() {
        NCAPIController.sharedInstance().removeUserProfileImage(for: account) { error, _ in
            if error == nil {
                self.refreshUserProfile()
            } else {
                self.showProfileImageError(NSLocalizedString("An error occurred removing profile image", comment: ""))
                print("Error removing profile image: ", error.debugDescription)
            }
        }
    }

    func showProfileImageError(_ reason: String) {
        let errorDialog = UIAlertController(title: reason, message: nil, preferredStyle: .alert)
        let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil)
        errorDialog.addAction(okAction)
        self.present(errorDialog, animated: true, completion: nil)
    }
}
