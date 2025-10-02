//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import libPhoneNumber

extension UserProfileTableViewController {

    @objc func editButtonPressed() {
        if activeTextField != nil {
            self.waitingForModification = true
            activeTextField?.resignFirstResponder()
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
            NCConnectionController.shared.checkAppState()
        }
    }

    func presentSetPhoneNumberDialog() {
        let setPhoneNumberDialog = UIAlertController(title: NSLocalizedString("Phone number", comment: ""), message: nil, preferredStyle: .alert)
        let hasPhone = !account.phone.isEmpty
        setPhoneNumberDialog.addTextField { [self] textField in
            let regionCode = NSLocale.current.regionCode
            let countryCode = NBPhoneNumberUtil.sharedInstance().getCountryCode(forRegion: regionCode)
            if let countryCode = countryCode {
                textField.text = "+\(countryCode)"
            }
            if hasPhone {
                textField.text = self.account.phone
            }
            let exampleNumber = try? NBPhoneNumberUtil.sharedInstance().getExampleNumber(regionCode ?? "")
            if let exampleNumber = exampleNumber {
                textField.placeholder = try? NBPhoneNumberUtil.sharedInstance().format(exampleNumber, numberFormat: NBEPhoneNumberFormat.INTERNATIONAL)
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
