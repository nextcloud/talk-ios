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

    // MARK: User Interface

    func showEditButton() {
        self.editButton = UIBarButtonItem(barButtonSystemItem: UIBarButtonItem.SystemItem.edit, target: self, action: #selector(editButtonPressed))
        self.editButton.accessibilityHint = NSLocalizedString("Double tap to edit profile", comment: "")
        self.navigationItem.rightBarButtonItem = editButton
    }

    func showDoneButton() {
        self.editButton = UIBarButtonItem(barButtonSystemItem: UIBarButtonItem.SystemItem.done, target: self, action: #selector(editButtonPressed))
        self.editButton.accessibilityHint = NSLocalizedString("Double tap to end editing profile", comment: "")
        self.navigationItem.rightBarButtonItem = editButton
    }

    func setModifyingProfileUI() {
        modifyingProfileView.startAnimating()
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: modifyingProfileView)
        self.tableView.isUserInteractionEnabled = false
    }

    func removeModifyingProfileUI() {
        modifyingProfileView.stopAnimating()
        if isEditable {
            self.showDoneButton()
        } else {
            self.showEditButton()
        }
        self.tableView.isUserInteractionEnabled = true
    }

    func refreshProfileTableView() {
        tableView.tableHeaderView = self.avatarHeaderView()
        tableView.tableHeaderView?.setNeedsDisplay()
        tableView.reloadData()
    }

    func getUserProfileEditableFields() {
        editButton.isEnabled = false
        NCAPIController.sharedInstance().getUserProfileEditableFields(for: account) { userProfileEditableFields, error in
            if error == nil {
                if let userProfileEditableFields = userProfileEditableFields as NSArray? {
                    self.editableFields = userProfileEditableFields
                    self.editButton.isEnabled = true
                }
            }
        }
    }

    func refreshUserProfile() {
        NCSettingsController.sharedInstance().getUserProfile { _ in
            self.account = NCDatabaseManager.sharedInstance().activeAccount()
            self.refreshProfileTableView()
        }
    }

    func showProfileModificationErrorForField(inTextField field: Int, textField: UITextField?) {
        var errorDescription = ""
        // The textfield pointer might be pointing to a different textfield at this point because
        // if the user tapped the "Done" button in navigation bar (so the non-editable view is visible)
        // That's the reason why we check the field instead of textfield.tag
        switch field {
        case kNameTextFieldTag:
            errorDescription = NSLocalizedString("An error occurred setting user name", comment: "")
        case kEmailTextFieldTag:
            errorDescription = NSLocalizedString("An error occurred setting email address", comment: "")
        case kPhoneTextFieldTag:
            errorDescription = NSLocalizedString("An error occurred setting phone number", comment: "")
        case kAddressTextFieldTag:
            errorDescription = NSLocalizedString("An error occurred setting address", comment: "")
        case kWebsiteTextFieldTag:
            errorDescription = NSLocalizedString("An error occurred setting website", comment: "")
        case kTwitterTextFieldTag:
            errorDescription = NSLocalizedString("An error occurred setting Twitter account", comment: "")
        default:
            break
        }
        let errorDialog = UIAlertController(title: errorDescription, message: nil, preferredStyle: .alert)
        let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { _ in
            if self.isEditable {
                textField?.becomeFirstResponder()
            }
        }
        errorDialog.addAction(okAction)
        self.present(errorDialog, animated: true, completion: nil)
    }

    func imageForScope(scope: String) -> UIImage? {
        if scope == kUserProfileScopePrivate {
            return UIImage(named: "mobile-phone-20")?.withRenderingMode(.alwaysTemplate)
        } else if scope == kUserProfileScopeLocal {
            return UIImage(named: "password-20")?.withRenderingMode(.alwaysTemplate)
        } else if scope == kUserProfileScopeFederated {
            return UIImage(named: "group-20")?.withRenderingMode(.alwaysTemplate)
        } else if scope == kUserProfileScopePublished {
            return UIImage(named: "browser-20")?.withRenderingMode(.alwaysTemplate)
        }
        return nil
    }

    @objc func showScopeSelectionDialog( _ sender: UIButton?) {
        var field: String?
        var currentValue: String?
        var title: String?
        guard let sender = sender else {
            return
        }
        switch sender.tag {
        case kNameTextFieldTag:
            setupFieldsForScopeSelectionDialog(field: &field, currentValue: &currentValue, title: &title,
                                               fieldValue: kUserProfileDisplayNameScope, currentValueText: account.userDisplayNameScope, titleValue: "Full name")
        case kEmailTextFieldTag:
            setupFieldsForScopeSelectionDialog(field: &field, currentValue: &currentValue, title: &title,
                                               fieldValue: kUserProfileEmailScope, currentValueText: account.emailScope, titleValue: "Email")
        case kPhoneTextFieldTag:
            setupFieldsForScopeSelectionDialog(field: &field, currentValue: &currentValue, title: &title,
                                               fieldValue: kUserProfilePhoneScope, currentValueText: account.phoneScope, titleValue: "Phone number")
        case kAddressTextFieldTag:
            setupFieldsForScopeSelectionDialog(field: &field, currentValue: &currentValue, title: &title,
                                               fieldValue: kUserProfileAddressScope, currentValueText: account.addressScope, titleValue: "Address")
        case kWebsiteTextFieldTag:
            setupFieldsForScopeSelectionDialog(field: &field, currentValue: &currentValue, title: &title,
                                               fieldValue: kUserProfileWebsiteScope, currentValueText: account.websiteScope, titleValue: "Website")
        case kTwitterTextFieldTag:
            setupFieldsForScopeSelectionDialog(field: &field, currentValue: &currentValue, title: &title,
                                               fieldValue: kUserProfileTwitterScope, currentValueText: account.twitterScope, titleValue: "Twitter")
        case kAvatarScopeButtonTag:
            setupFieldsForScopeSelectionDialog(field: &field, currentValue: &currentValue, title: &title,
                                               fieldValue: kUserProfileAvatarScope, currentValueText: account.avatarScope, titleValue: "Profile picture")
        default:
            break
        }
        var options = [DetailedOption]()
        let privateOption = setupDetailedOption(identifier: kUserProfileScopePrivate, imageName: "mobile-phone", title: NSLocalizedString("Private", comment: ""),
                                                subtitle: NSLocalizedString("Only visible to people matched via phone number integration", comment: ""),
                                                selected: currentValue == kUserProfileScopePrivate)
        let localOption = setupDetailedOption(identifier: kUserProfileScopeLocal, imageName: "password-settings", title: NSLocalizedString("Local", comment: ""),
                                              subtitle: NSLocalizedString("Only visible to people on this instance and guests", comment: ""), selected: currentValue == kUserProfileScopeLocal)
        let federatedOption = setupDetailedOption(identifier: kUserProfileScopeFederated, imageName: "group", title: NSLocalizedString("Federated", comment: ""),
                                                  subtitle: NSLocalizedString("Only synchronize to trusted servers", comment: ""), selected: currentValue == kUserProfileScopeFederated)
        let publishedOption = setupDetailedOption(identifier: kUserProfileScopePublished, imageName: "browser-settings", title: NSLocalizedString("Published", comment: ""),
                                                  subtitle: NSLocalizedString("Synchronize to trusted servers and the global and public address book", comment: ""),
                                                  selected: currentValue == kUserProfileScopePublished)
        if field != kUserProfileDisplayNameScope && field != kUserProfileEmailScope {
            options.append(privateOption)
        }
        options.append(localOption)
        let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId)
        if serverCapabilities.accountPropertyScopesFederationEnabled {
            options.append(federatedOption)
            options.append(publishedOption)
        }
        let optionSelectorVC = DetailedOptionsSelectorTableViewController(options: options, forSenderIdentifier: field, andTitle: title)
        if let optionSelectorVC = optionSelectorVC {
            optionSelectorVC.delegate = self
            let optionSelectorNC = UINavigationController(rootViewController: optionSelectorVC)
            self.present(optionSelectorNC, animated: true, completion: nil)
        }
    }

    func setUserProfileField(_ field: String?, scopeValue scope: String?) {
        setModifyingProfileUI()
        NCAPIController.sharedInstance().setUserProfileField(field, withValue: scope, for: account) { [self] error, _ in
            if error != nil {
                showScopeModificationError()
            } else {
                refreshUserProfile()
            }
            removeModifyingProfileUI()
        }
    }

    func showScopeModificationError() {
        let errorDialog = UIAlertController(title: NSLocalizedString("An error occurred changing privacy setting", comment: ""), message: nil, preferredStyle: .alert)
        let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil)
        errorDialog.addAction(okAction)
        self.present(errorDialog, animated: true, completion: nil)
    }

    // Setup Dialog Options
    func setupDetailedOption(identifier: String, imageName: String, title: String, subtitle: String, selected: Bool) -> DetailedOption {
        let detailedOption = DetailedOption()
        detailedOption.identifier = identifier
        detailedOption.image = UIImage(named: imageName)?.withRenderingMode(.alwaysTemplate)
        detailedOption.title = title
        detailedOption.subtitle = subtitle
        detailedOption.selected = selected
        return detailedOption
    }

    func setupFieldsForScopeSelectionDialog(field: inout String?, currentValue: inout String?, title: inout String?, fieldValue: String, currentValueText: String, titleValue: String) {
        field = fieldValue
        currentValue = currentValueText
        title = NSLocalizedString(titleValue, comment: "")
    }

    func getProfileSections() -> [Int] {
        var sections: [Int] = []
        if isEditable {
            sections.append(ProfileSection.kProfileSectionName.rawValue)
            sections.append(ProfileSection.kProfileSectionEmail.rawValue)
            sections.append(ProfileSection.kProfileSectionPhoneNumber.rawValue)
            sections.append(ProfileSection.kProfileSectionAddress.rawValue)
            sections.append(ProfileSection.kProfileSectionWebsite.rawValue)
            sections.append(ProfileSection.kProfileSectionTwitter.rawValue)
        } else if !(self.rowsInSummarySection().isEmpty) {
            sections.append(ProfileSection.kProfileSectionSummary.rawValue)
        }
        if multiAccountEnabled.boolValue {
            sections.append(ProfileSection.kProfileSectionAddAccount.rawValue)
        }
        sections.append(ProfileSection.kProfileSectionRemoveAccount.rawValue)
        return sections
    }

    func rowsInSummarySection() -> [Int] {
        var rows = [Int]()
        if !account.email.isEmpty {
            rows.append(SummaryRow.kSummaryRowEmail.rawValue)
        }
        if !account.phone.isEmpty {
            rows.append(SummaryRow.kSummaryRowPhoneNumber.rawValue)
        }
        if !account.address.isEmpty {
            rows.append(SummaryRow.kSummaryRowAddress.rawValue)
        }
        if !account.website.isEmpty {
            rows.append(SummaryRow.kSummaryRowWebsite.rawValue)
        }
        if !account.twitter.isEmpty {
            rows.append(SummaryRow.kSummaryRowTwitter.rawValue)
        }
        return rows
    }
}
