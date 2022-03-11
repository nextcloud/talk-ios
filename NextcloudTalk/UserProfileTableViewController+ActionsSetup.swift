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

    // MARK: Actions

    @objc func editButtonPressed() {
        if activeTextField != nil {
            self.waitingForModification = true
            return
        }
        if !isEditable {
            isEditable = true
            self.showDoneButton()
        } else {
            isEditable = false
            self.showEditButton()
        }
        self.refreshProfileTableView()
    }

    func addNewAccount() {
        self.dismiss(animated: true) {
            NCUserInterfaceController.sharedInstance().presentLoginViewController()
        }
    }

    func showLogoutConfirmationDialog() {
        let alertTitle = multiAccountEnabled.boolValue ? NSLocalizedString("Remove account", comment: "") : NSLocalizedString("Log out", comment: "")
        let alertMessageAccountRemove = NSLocalizedString("Do you really want to remove this account?", comment: "")
        let alertMessageAccountLogout = NSLocalizedString("Do you really want to log out from this account?", comment: "")
        let alertMessage = multiAccountEnabled.boolValue ? alertMessageAccountRemove : alertMessageAccountLogout
        let actionTitle = multiAccountEnabled.boolValue ? NSLocalizedString("Remove", comment: "") : NSLocalizedString("Log out", comment: "")
        let confirmDialog = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: .alert)
        let confirmAction = UIAlertAction(title: actionTitle, style: .destructive) { _ in
            self.logout()
        }
        confirmDialog.addAction(confirmAction)
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
        confirmDialog.addAction(cancelAction)
        self.present(confirmDialog, animated: true, completion: nil)
    }

    func logout() {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCSettingsController.sharedInstance().logoutAccount(withAccountId: activeAccount.accountId) { _ in
            NCUserInterfaceController.sharedInstance().presentConversationsList()
            NCConnectionController.sharedInstance().checkAppState()
        }
    }

    func presentSetPhoneNumberDialog() {
        let setPhoneNumberDialog = UIAlertController(title: NSLocalizedString("Phone number", comment: ""), message: nil, preferredStyle: .alert)
        let hasPhone = !account.phone.isEmpty
        setPhoneNumberDialog.addTextField { [self] textField in
            let location = NSLocale.current.regionCode
            let countryCode = phoneUtil?.getCountryCode(forRegion: location)
            if let countryCode = countryCode {
                textField.text = "+\(countryCode)"
            }
            if hasPhone {
                textField.text = self.account.phone
            }
            let exampleNumber = try? self.phoneUtil?.getExampleNumber(location ?? "")
            if let exampleNumber = exampleNumber {
                textField.placeholder = try? self.phoneUtil?.format(exampleNumber, numberFormat: NBEPhoneNumberFormat.INTERNATIONAL)
                textField.keyboardType = .phonePad
                textField.delegate = self
                textField.tag = self.kPhoneTextFieldTag
            }
        }
        setPhoneAction = UIAlertAction(title: NSLocalizedString("Set", comment: ""), style: .default, handler: { _ in
            let phoneNumber = setPhoneNumberDialog.textFields?[0].text
            if let phoneNumber = phoneNumber {
                self.setPhoneNumber(phoneNumber)
            }
        })
        setPhoneAction.isEnabled = false
        setPhoneNumberDialog.addAction(setPhoneAction)
        if hasPhone {
            let removeAction = UIAlertAction(title: NSLocalizedString("Remove", comment: ""), style: .destructive) { _ in
                self.setPhoneNumber("")
            }
            setPhoneNumberDialog.addAction(removeAction)
        }
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
        setPhoneNumberDialog.addAction(cancelAction)
        self.present(setPhoneNumberDialog, animated: true, completion: nil)
    }

    func setPhoneNumber(_ phoneNumber: String) {
        self.setModifyingProfileUI()
        NCAPIController.sharedInstance().setUserProfileField(kUserProfilePhone, withValue: phoneNumber, for: account) { error, _ in
            if error != nil {
                self.showProfileModificationErrorForField(inTextField: self.kPhoneTextFieldTag, textField: nil)
            } else {
                self.refreshUserProfile()
            }
            self.removeModifyingProfileUI()
        }
    }
}
