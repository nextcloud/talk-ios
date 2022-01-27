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

extension UserProfileTableViewController: UINavigationControllerDelegate, UITextFieldDelegate, UIGestureRecognizerDelegate, UIImagePickerControllerDelegate {

    // MARK: DetailedOptionSelector Delegate

    func detailedOptionsSelector(_ viewController: DetailedOptionsSelectorTableViewController!, didSelectOptionWithIdentifier option: DetailedOption!) {
        self.dismiss(animated: true) {
            if !option.selected {
                self.setUserProfileField(viewController.senderId, scopeValue: option.identifier)
            }
        }
    }

    func detailedOptionsSelectorWasCancelled(_ viewController: DetailedOptionsSelectorTableViewController!) {
        self.dismiss(animated: true, completion: nil)
    }

    // MARK: UIImagePickerController Delegate

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

    // MARK: TOCROPViewControllerDelegate

    func cropViewController(_ cropViewController: TOCropViewController, didCropTo image: UIImage, with cropRect: CGRect, angle: Int) {
        self.sendUserProfileImage(image: image)
        // Fixes weird iOS 13 bug: https://github.com/TimOliver/TOCropViewController/issues/365
        cropViewController.transitioningDelegate = nil
        cropViewController.dismiss(animated: true)
    }

    func cropViewController(_ cropViewController: TOCropViewController, didFinishCancelled cancelled: Bool) {
        // Fixes weird iOS 13 bug: https://github.com/TimOliver/TOCropViewController/issues/365
        cropViewController.transitioningDelegate = nil
        cropViewController.dismiss(animated: true)
    }

    // MARK: UITextField delegate

    func textFieldDidBeginEditing(_ textField: UITextField) {
        activeTextField = textField
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        var field: String?
        var currentValue: String?
        let newValue = textField.text!.trimmingCharacters(in: CharacterSet.whitespaces)
        let tag = textField.tag
        let waitForModification = self.waitingForModification
        self.waitingForModification = false
        activeTextField = nil
        if tag == kNameTextFieldTag {
            field = kUserProfileDisplayName
            currentValue = account.userDisplayName
        } else if tag == kEmailTextFieldTag {
            field = kUserProfileEmail
            currentValue = account.email
        } else if tag == kPhoneTextFieldTag {
            return
        } else if tag == kAddressTextFieldTag {
            field = kUserProfileAddress
            currentValue = account.address
        } else if tag == kWebsiteTextFieldTag {
            field = kUserProfileWebsite
            currentValue = account.website
        } else if tag == kTwitterTextFieldTag {
            field = kUserProfileTwitter
            currentValue = account.twitter
        }
        textField.text = newValue
        self.setModifyingProfileUI()
        if newValue != currentValue {
            NCAPIController.sharedInstance().setUserProfileField(field, withValue: newValue, for: account) { error, _ in
                if error != nil {
                    self.showProfileModificationErrorForField(inTextField: tag, textField: textField)
                } else {
                    if waitForModification {
                        self.editButtonPressed()
                    }
                    self.refreshUserProfile()
                }
                self.removeModifyingProfileUI()
            }
        } else {
            if waitForModification {
                self.editButtonPressed()
            }
            self.removeModifyingProfileUI()
        }
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if textField.tag == kPhoneTextFieldTag {
            let inputPhoneNumber = (textField.text as NSString?)?.replacingCharacters(in: range, with: string)
            var phoneNumber: NBPhoneNumber?
            phoneNumber = try? phoneUtil?.parse(inputPhoneNumber, defaultRegion: nil)
            setPhoneAction.isEnabled = (phoneUtil?.isValidNumber(phoneNumber))! && (account.phone != inputPhoneNumber)
        }
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
