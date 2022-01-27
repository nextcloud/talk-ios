/**
 * @copyright Copyright (c) 2022 Aleksandra Lazarevic <aleksandra@nextcloud.com>
 *
 * @author Aleksandra Lazarevic <aleksandra@nextcloud.com>
 *
 * @license GNU GPL version 3 or any later version
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

import Foundation

extension UserProfileTableViewController {

    func avatarHeaderView() -> UIView? {
        let headerView = AvatarHeaderView()
        headerView.frame = CGRect(x: 0, y: 0, width: 200, height: 150)
        headerView.avatarImageView?.layer.cornerRadius = 40.0
        headerView.avatarImageView?.layer.masksToBounds = true
        headerView.avatarImageView?.image = NCAPIController.sharedInstance().userProfileImage(for: account, with: CGSize(width: 160, height: 160))
        headerView.nameLabel?.text = account.userDisplayName
        headerView.nameLabel?.isHidden = self.isEditable
        headerView.scopeButton?.tag = kAvatarScopeButtonTag
        headerView.scopeButton?.setImage(self.imageForScope(scope: account.avatarScope), for: .normal)
        headerView.scopeButton?.addTarget(self, action: #selector(showScopeSelectionDialog(_:)), for: .touchUpInside)
        headerView.scopeButton?.isHidden = !(isEditable && (showScopes != nil))
        headerView.editButton?.isHidden = !(isEditable && NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityTempUserAvatarAPI, forAccountId: account.accountId))
        headerView.editButton?.setTitle(NSLocalizedString("Edit", comment: ""), for: .normal)
        headerView.editButton?.addTarget(self, action: #selector(showAvatarOptions), for: .touchUpInside)
        if let editButton = headerView.editButton {
            editAvatarButton = editButton
        }
        return headerView
    }

    @objc func showAvatarOptions() {
        let optionsActionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let cameraAction = UIAlertAction(title: NSLocalizedString("Camera", comment: ""), style: .default) { _ in
            self.checkAndPresentCamera()
        }
        cameraAction.setValue(UIImage(named: "camera")?.withRenderingMode(.alwaysTemplate), forKey: "image")
        let photoLibraryAction = UIAlertAction(title: NSLocalizedString("Photo Library", comment: ""), style: .default) { _ in
            self.presentPhotoLibrary()
        }
        photoLibraryAction.setValue(UIImage(named: "photos")?.withRenderingMode(.alwaysTemplate), forKey: "image")
        let removeAction = UIAlertAction(title: NSLocalizedString("Remove", comment: ""), style: .destructive) { _ in
            self.removeUserProfileImage()
        }
        removeAction.setValue(UIImage(named: "delete")?.withRenderingMode(.alwaysTemplate), forKey: "image")
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            optionsActionSheet.addAction(cameraAction)
        }
        optionsActionSheet.addAction(photoLibraryAction)
        if account.hasCustomAvatar {
            optionsActionSheet.addAction(removeAction)
        }
        optionsActionSheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
        // Presentation on iPads
        optionsActionSheet.popoverPresentationController?.sourceView = editAvatarButton
        optionsActionSheet.popoverPresentationController?.sourceRect = editAvatarButton.frame
        self.present(optionsActionSheet, animated: true, completion: nil)
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
