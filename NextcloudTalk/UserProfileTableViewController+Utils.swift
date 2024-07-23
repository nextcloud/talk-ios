//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

extension UserProfileTableViewController {

    // MARK: - User Profile

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
        NCSettingsController.sharedInstance().getUserProfile(forAccountId: account.accountId) { _ in
            self.account = NCDatabaseManager.sharedInstance().activeAccount()
            self.refreshProfileTableView()
        }
    }

    // MARK: - Notifications

    @objc func userProfileImageUpdated(notification: NSNotification) {
        self.account = NCDatabaseManager.sharedInstance().activeAccount()
        self.refreshProfileTableView()
    }

    // MARK: - Sections

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

    // MARK: - User Interface

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
            return UIImage(systemName: "iphone")
        } else if scope == kUserProfileScopeLocal {
            return UIImage(systemName: "lock")
        } else if scope == kUserProfileScopeFederated {
            return UIImage(systemName: "person.2")
        } else if scope == kUserProfileScopePublished {
            return UIImage(systemName: "network")
        }
        return nil
    }

    @objc func showScopeSelectionDialog( _ sender: UIButton?) {
        guard let sender = sender else {
            return
        }

        let field: String
        let currentValue: String
        let title: String

        if sender.tag == kNameTextFieldTag {
            field = kUserProfileDisplayNameScope
            currentValue = account.userDisplayNameScope
            title = NSLocalizedString("Full name", comment: "")
        } else if sender.tag == kEmailTextFieldTag {
            field = kUserProfileEmailScope
            currentValue = account.emailScope
            title = NSLocalizedString("Email", comment: "")
        } else if sender.tag == kPhoneTextFieldTag {
            field = kUserProfilePhoneScope
            currentValue = account.phoneScope
            title = NSLocalizedString("Phone number", comment: "")
        } else if sender.tag == kAddressTextFieldTag {
            field = kUserProfileAddressScope
            currentValue = account.addressScope
            title = NSLocalizedString("Address", comment: "")
        } else if sender.tag == kWebsiteTextFieldTag {
            field = kUserProfileWebsiteScope
            currentValue = account.websiteScope
            title = NSLocalizedString("Website", comment: "")
        } else if sender.tag == kTwitterTextFieldTag {
            field = kUserProfileTwitterScope
            currentValue = account.twitterScope
            title = NSLocalizedString("Twitter", comment: "")
        } else if sender.tag == kAvatarScopeButtonTag {
            field = kUserProfileAvatarScope
            currentValue = account.avatarScope
            title = NSLocalizedString("Profile picture", comment: "")
        } else {
            return
        }

        presentScopeSelector(field: field, currentValue: currentValue, title: title)
    }

    func presentScopeSelector(field: String, currentValue: String, title: String) {
        var options = [DetailedOption]()

        let privateOption = setupDetailedOption(identifier: kUserProfileScopePrivate,
                                                image: UIImage(systemName: "iphone")?.applyingSymbolConfiguration(iconConfiguration),
                                                title: NSLocalizedString("Private", comment: ""),
                                                subtitle: NSLocalizedString("Only visible to people matched via phone number integration", comment: ""),
                                                selected: currentValue == kUserProfileScopePrivate)
        let localOption = setupDetailedOption(identifier: kUserProfileScopeLocal,
                                              image: UIImage(systemName: "lock")?.applyingSymbolConfiguration(iconConfiguration),
                                              title: NSLocalizedString("Local", comment: ""),
                                              subtitle: NSLocalizedString("Only visible to people on this instance and guests", comment: ""),
                                              selected: currentValue == kUserProfileScopeLocal)
        let federatedOption = setupDetailedOption(identifier: kUserProfileScopeFederated,
                                                  image: UIImage(systemName: "person.2")?.applyingSymbolConfiguration(iconConfiguration),
                                                  title: NSLocalizedString("Federated", comment: ""),
                                                  subtitle: NSLocalizedString("Only synchronize to trusted servers", comment: ""),
                                                  selected: currentValue == kUserProfileScopeFederated)
        let publishedOption = setupDetailedOption(identifier: kUserProfileScopePublished,
                                                  image: UIImage(systemName: "network")?.applyingSymbolConfiguration(iconConfiguration),
                                                  title: NSLocalizedString("Published", comment: ""),
                                                  subtitle: NSLocalizedString("Synchronize to trusted servers and the global and public address book", comment: ""),
                                                  selected: currentValue == kUserProfileScopePublished)

        if field != kUserProfileDisplayNameScope && field != kUserProfileEmailScope {
            options.append(privateOption)
        }

        options.append(localOption)

        if let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId) {
            // Legacy capability
            if serverCapabilities.accountPropertyScopesFederationEnabled {
                options.append(federatedOption)
                options.append(publishedOption)
            }
            if serverCapabilities.accountPropertyScopesFederatedEnabled {
                options.append(federatedOption)
            }
            if serverCapabilities.accountPropertyScopesPublishedEnabled {
                options.append(publishedOption)
            }
        }

        let optionSelectorVC = DetailedOptionsSelectorTableViewController(options: options, forSenderIdentifier: field, andStyle: .insetGrouped)
        if let optionSelectorVC = optionSelectorVC {
            optionSelectorVC.title = title
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
    func setupDetailedOption(identifier: String, image: UIImage?, title: String, subtitle: String, selected: Bool) -> DetailedOption {
        let detailedOption = DetailedOption()
        detailedOption.identifier = identifier
        detailedOption.image = image
        detailedOption.title = title
        detailedOption.subtitle = subtitle
        detailedOption.selected = selected
        return detailedOption
    }
}
