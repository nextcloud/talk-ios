//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import libPhoneNumber

enum ProfileSection: Int {
    case kProfileSectionName = 0
    case kProfileSectionEmail
    case kProfileSectionPhoneNumber
    case kProfileSectionAddress
    case kProfileSectionWebsite
    case kProfileSectionTwitter
    case kProfileSectionSummary
    case kProfileSectionRemoveAccount
}

enum SummaryRow: Int {
    case kSummaryRowEmail = 0
    case kSummaryRowPhoneNumber
    case kSummaryRowAddress
    case kSummaryRowWebsite
    case kSummaryRowTwitter
}

@objcMembers
class UserProfileTableViewController: UITableViewController, DetailedOptionsSelectorTableViewControllerDelegate, TOCropViewControllerDelegate {

    let kNameTextFieldTag       = 99
    let kEmailTextFieldTag      = 98
    let kPhoneTextFieldTag      = 97
    let kAddressTextFieldTag    = 96
    let kWebsiteTextFieldTag    = 95
    let kTwitterTextFieldTag    = 94
    let kAvatarScopeButtonTag   = 93

    let iconConfiguration = UIImage.SymbolConfiguration(pointSize: 18)
    let iconHeaderConfiguration = UIImage.SymbolConfiguration(pointSize: 13)

    var account = TalkAccount()
    var isEditable = Bool()
    var waitingForModification = Bool()
    var editButton = UIBarButtonItem()
    var activeTextField: UITextField?
    var modifyingProfileView = UIActivityIndicatorView()
    var imagePicker: UIImagePickerController?
    var setPhoneAction = UIAlertAction()
    var editableFields = NSArray()
    var showScopes = Bool()

    override func viewDidLoad() {
        super.viewDidLoad()

        NCAppBranding.styleViewController(self)

        self.navigationItem.title = NSLocalizedString("Profile", comment: "")

        self.tableView.tableHeaderView = self.avatarHeaderView()
        self.showEditButton()
        self.getUserProfileEditableFields()

        if let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId) {
            showScopes = serverCapabilities.accountPropertyScopesVersion2
        }

        modifyingProfileView = UIActivityIndicatorView()
        modifyingProfileView.color = NCAppBranding.themeTextColor()
        tableView.keyboardDismissMode = UIScrollView.KeyboardDismissMode.onDrag
        tableView.register(TextFieldTableViewCell.self, forCellReuseIdentifier: TextFieldTableViewCell.identifier)
        NotificationCenter.default.addObserver(self, selector: #selector(userProfileImageUpdated), name: NSNotification.Name.NCUserProfileImageUpdated, object: nil)

        if navigationController?.viewControllers.first == self {
            let barButtonItem = UIBarButtonItem(title: nil, style: .plain, target: nil, action: nil)
            barButtonItem.primaryAction = UIAction(title: NSLocalizedString("Close", comment: ""), handler: { [unowned self] _ in
                self.dismiss(animated: true)
            })
            self.navigationItem.leftBarButtonItems = [barButtonItem]
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Workaround to fix label width
        guard let headerView = self.tableView.tableHeaderView as? AvatarEditView else {return}
        guard var labelFrame = headerView.nameLabel?.frame else {return}
        let padding: CGFloat = 16
        labelFrame.origin.x = padding
        labelFrame.size.width = self.tableView.bounds.size.width - padding * 2
        headerView.nameLabel?.frame = labelFrame
    }

    init(withAccount account: TalkAccount) {
        super.init(style: .insetGrouped)
        self.account = account
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return self.getProfileSections().count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sections = self.getProfileSections()
        let profileSection = sections[section]
        if profileSection == ProfileSection.kProfileSectionSummary.rawValue {
            return self.rowsInSummarySection().count
        }
        return 1
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let sections = self.getProfileSections()
        let profileSection = sections[section]
        switch profileSection {
        case ProfileSection.kProfileSectionName.rawValue,
            ProfileSection.kProfileSectionEmail.rawValue,
            ProfileSection.kProfileSectionPhoneNumber.rawValue,
            ProfileSection.kProfileSectionAddress.rawValue,
            ProfileSection.kProfileSectionWebsite.rawValue,
            ProfileSection.kProfileSectionTwitter.rawValue,
            ProfileSection.kProfileSectionRemoveAccount.rawValue:
            return 40
        case ProfileSection.kProfileSectionSummary.rawValue:
            return 20
        default:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let sections = self.getProfileSections()
        let profileSection = sections[section]
        let headerView = setupViewforHeaderInSection(profileSection: profileSection)
        if headerView.button.tag != 0 {
            return headerView
        }
        return nil
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        let sections = self.getProfileSections()
        let profileSection = sections[section]
        if profileSection == ProfileSection.kProfileSectionEmail.rawValue {
            return NSLocalizedString("For password reset and notifications", comment: "")
        }
        return nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = self.getProfileSections()[indexPath.section]
        switch section {
        case ProfileSection.kProfileSectionName.rawValue:
            return textInputCellWith(text: account.userDisplayName,
                                     tag: kNameTextFieldTag,
                                     interactionEnabled: editableFields.contains(kUserProfileDisplayName))
        case ProfileSection.kProfileSectionEmail.rawValue:
            return textInputCellWith(text: account.email,
                                     tag: kEmailTextFieldTag,
                                     interactionEnabled: editableFields.contains(kUserProfileEmail),
                                     keyBoardType: .emailAddress,
                                     autocapitalizationType: .none,
                                     placeHolder: NSLocalizedString("Your email address", comment: ""))
        case ProfileSection.kProfileSectionPhoneNumber.rawValue:
            let phoneNumber = try? NBPhoneNumberUtil.sharedInstance().parse(account.phone, defaultRegion: nil)
            let text = (phoneNumber != nil) ? try? NBPhoneNumberUtil.sharedInstance().format(phoneNumber, numberFormat: NBEPhoneNumberFormat.INTERNATIONAL) : nil
            return textInputCellWith(text: text,
                                     tag: kPhoneTextFieldTag,
                                     interactionEnabled: false,
                                     keyBoardType: .phonePad,
                                     autocapitalizationType: .none,
                                     placeHolder: NSLocalizedString("Your phone number", comment: ""))
        case ProfileSection.kProfileSectionAddress.rawValue:
            return textInputCellWith(text: account.address,
                                     tag: kAddressTextFieldTag,
                                     interactionEnabled: editableFields.contains(kUserProfileAddress),
                                     placeHolder: NSLocalizedString("Your postal address", comment: ""))
        case ProfileSection.kProfileSectionWebsite.rawValue:
            return textInputCellWith(text: account.website,
                                     tag: kWebsiteTextFieldTag,
                                     interactionEnabled: editableFields.contains(kUserProfileWebsite),
                                     keyBoardType: .URL,
                                     autocapitalizationType: .none,
                                     placeHolder: NSLocalizedString("Link https://…", comment: ""))
        case ProfileSection.kProfileSectionTwitter.rawValue:
            return textInputCellWith(text: account.twitter,
                                     tag: kTwitterTextFieldTag,
                                     interactionEnabled: editableFields.contains(kUserProfileTwitter),
                                     keyBoardType: .emailAddress,
                                     autocapitalizationType: .none,
                                     placeHolder: NSLocalizedString("Twitter handle @…", comment: ""))
        case ProfileSection.kProfileSectionSummary.rawValue:
            return summaryCellForRow(row: indexPath.row)
        case ProfileSection.kProfileSectionRemoveAccount.rawValue:
            let actionTitle = multiAccountEnabled.boolValue ? NSLocalizedString("Remove account", comment: "") : NSLocalizedString("Log out", comment: "")
            let actionImage = multiAccountEnabled.boolValue ?
            UIImage(systemName: "trash")?.applyingSymbolConfiguration(iconConfiguration) :
            UIImage(systemName: "arrow.right.square")?.applyingSymbolConfiguration(iconConfiguration)
            return actionCellWith(identifier: "RemoveAccountCellIdentifier", text: actionTitle, textColor: .systemRed, image: actionImage, tintColor: .systemRed)
        default:
            break
        }
        return UITableViewCell()
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let sections = getProfileSections()
        let section = sections[indexPath.section]
        if section == ProfileSection.kProfileSectionRemoveAccount.rawValue {
            self.showLogoutConfirmationDialog()
        } else if section == ProfileSection.kProfileSectionPhoneNumber.rawValue {
            self.presentSetPhoneNumberDialog()
        }
        self.tableView.deselectRow(at: indexPath, animated: true)
    }
}

extension UserProfileTableViewController {

    // MARK: Header View Setup

    func setupViewForSection(headerView: inout HeaderWithButton, title: String, buttonTag: Int, enabled: Bool?, scopeForImage: String) {
        headerView.label.text = title.uppercased()
        headerView.button.tag = buttonTag
        if let enabled = enabled {
            headerView.button.isEnabled = enabled
        }
        headerView.button.setImage(self.imageForScope(scope: scopeForImage)?.applyingSymbolConfiguration(iconHeaderConfiguration), for: .normal)
    }

    func setupViewforHeaderInSection(profileSection: Int) -> HeaderWithButton {
        var headerView = HeaderWithButton()
        headerView.button.addTarget(self, action: #selector(showScopeSelectionDialog(_:)), for: .touchUpInside)

        var shouldEnableNameAndEmailScopeButton = false

        if let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId) {
            shouldEnableNameAndEmailScopeButton = serverCapabilities.accountPropertyScopesFederationEnabled ||
            serverCapabilities.accountPropertyScopesFederatedEnabled || serverCapabilities.accountPropertyScopesPublishedEnabled
        }

        switch profileSection {
        case ProfileSection.kProfileSectionName.rawValue:
            setupViewForSection(headerView: &headerView, title: NSLocalizedString("Full name", comment: ""), buttonTag: kNameTextFieldTag,
                                enabled: shouldEnableNameAndEmailScopeButton, scopeForImage: account.userDisplayNameScope)
        case ProfileSection.kProfileSectionEmail.rawValue:
            setupViewForSection(headerView: &headerView, title: NSLocalizedString("Email", comment: ""), buttonTag: kEmailTextFieldTag,
                                enabled: shouldEnableNameAndEmailScopeButton, scopeForImage: account.emailScope)
        case ProfileSection.kProfileSectionPhoneNumber.rawValue:
            setupViewForSection(headerView: &headerView, title: NSLocalizedString("Phone number", comment: ""), buttonTag: kPhoneTextFieldTag,
                                enabled: nil, scopeForImage: account.phoneScope)
        case ProfileSection.kProfileSectionAddress.rawValue:
            setupViewForSection(headerView: &headerView, title: NSLocalizedString("Address", comment: ""), buttonTag: kAddressTextFieldTag,
                                enabled: nil, scopeForImage: account.addressScope)
        case ProfileSection.kProfileSectionWebsite.rawValue:
            setupViewForSection(headerView: &headerView, title: NSLocalizedString("Website", comment: ""), buttonTag: kWebsiteTextFieldTag,
                                enabled: nil, scopeForImage: account.websiteScope)
        case ProfileSection.kProfileSectionTwitter.rawValue:
            setupViewForSection(headerView: &headerView, title: NSLocalizedString("Twitter", comment: ""), buttonTag: kTwitterTextFieldTag,
                                enabled: nil, scopeForImage: account.twitterScope)
        default:
            break
        }
        return headerView
    }

    // MARK: Setup cells

    func textInputCellWith(text: String?, tag: Int, interactionEnabled: Bool, keyBoardType: UIKeyboardType = .default, autocapitalizationType: UITextAutocapitalizationType = .sentences, placeHolder: String = "") -> TextFieldTableViewCell {
        let textInputCell: TextFieldTableViewCell = tableView.dequeueOrCreateCell(withIdentifier: TextFieldTableViewCell.identifier)

        textInputCell.textField.delegate = self
        textInputCell.textField.text = text
        textInputCell.textField.tag = tag
        textInputCell.textField.isUserInteractionEnabled = interactionEnabled
        textInputCell.textField.keyboardType = keyBoardType
        textInputCell.textField.autocapitalizationType = autocapitalizationType
        textInputCell.textField.placeholder = placeHolder

        return textInputCell
    }

    func summaryCellForRow(row: Int) -> UITableViewCell {
        let summaryCell = tableView.dequeueReusableCell(withIdentifier: "SummaryCellIdentifier") ?? UITableViewCell(style: .default, reuseIdentifier: "SummaryCellIdentifier")
        let summaryRow = self.rowsInSummarySection()[row]
        switch summaryRow {
        case SummaryRow.kSummaryRowEmail.rawValue:
            summaryCell.textLabel?.text = account.email
            summaryCell.imageView?.image = UIImage(systemName: "envelope")?.applyingSymbolConfiguration(iconConfiguration)
        case SummaryRow.kSummaryRowPhoneNumber.rawValue:
            let phoneNumber = try? NBPhoneNumberUtil.sharedInstance().parse(account.phone, defaultRegion: nil)
            let text = (phoneNumber != nil) ? try? NBPhoneNumberUtil.sharedInstance().format(phoneNumber, numberFormat: NBEPhoneNumberFormat.INTERNATIONAL) : nil
            summaryCell.textLabel?.text = text
            summaryCell.imageView?.image = UIImage(systemName: "iphone")?.applyingSymbolConfiguration(iconConfiguration)
        case SummaryRow.kSummaryRowAddress.rawValue:
            summaryCell.textLabel?.text = account.address
            summaryCell.imageView?.image = UIImage(systemName: "mappin")?.applyingSymbolConfiguration(iconConfiguration)
        case SummaryRow.kSummaryRowWebsite.rawValue:
            summaryCell.textLabel?.text = account.website
            summaryCell.imageView?.image = UIImage(systemName: "network")?.applyingSymbolConfiguration(iconConfiguration)
        case SummaryRow.kSummaryRowTwitter.rawValue:
            summaryCell.textLabel?.text = account.twitter
            summaryCell.imageView?.image = UIImage(named: "twitter")?.withRenderingMode(.alwaysTemplate)
        default:
            break
        }

        summaryCell.imageView?.tintColor = .secondaryLabel

        return summaryCell
    }

    func actionCellWith(identifier: String, text: String, textColor: UIColor, image: UIImage?, tintColor: UIColor) -> UITableViewCell {
        let actionCell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell(style: .default, reuseIdentifier: identifier)

        actionCell.textLabel?.text = text
        actionCell.textLabel?.textColor = textColor
        actionCell.imageView?.image = image?.withRenderingMode(.alwaysTemplate)
        actionCell.imageView?.tintColor = tintColor

        return actionCell
    }
}
