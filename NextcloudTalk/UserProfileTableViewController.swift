//
// Copyright (c) 2022 Aleksandra Lazarevic <aleksandra@nextcloud.com>
//
// Author Aleksandra Lazarevic <aleksandra@nextcloud.com>
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

import UIKit

enum ProfileSection: Int {
    case kProfileSectionName = 0
    case kProfileSectionEmail
    case kProfileSectionPhoneNumber
    case kProfileSectionAddress
    case kProfileSectionWebsite
    case kProfileSectionTwitter
    case kProfileSectionSummary
    case kProfileSectionAddAccount
    case kProfileSectionRemoveAccount
}

enum SummaryRow: Int {
    case kSummaryRowEmail = 0
    case kSummaryRowPhoneNumber
    case kSummaryRowAddress
    case kSummaryRowWebsite
    case kSummaryRowTwitter
}

class UserProfileTableViewController: UITableViewController, DetailedOptionsSelectorTableViewControllerDelegate, TOCropViewControllerDelegate {

    let kNameTextFieldTag       = 99
    let kEmailTextFieldTag      = 98
    let kPhoneTextFieldTag      = 97
    let kAddressTextFieldTag    = 96
    let kWebsiteTextFieldTag    = 95
    let kTwitterTextFieldTag    = 94
    let kAvatarScopeButtonTag   = 93

    var account = TalkAccount()
    var isEditable = Bool()
    var waitingForModification = Bool()
    var editButton = UIBarButtonItem()
    var activeTextField: UITextField?
    var modifyingProfileView = UIActivityIndicatorView()
    var editAvatarButton = UIButton()
    var imagePicker: UIImagePickerController?
    var setPhoneAction = UIAlertAction()
    var phoneUtil = NBPhoneNumberUtil()
    var editableFields = NSArray()
    var showScopes = Bool()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationItem.title = NSLocalizedString("Profile", comment: "")
        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: NCAppBranding.themeTextColor()]
        self.navigationController?.navigationBar.tintColor = NCAppBranding.themeTextColor()
        self.navigationController?.navigationBar.barTintColor = NCAppBranding.themeColor()
        self.tabBarController?.tabBar.tintColor = NCAppBranding.themeColor()
        let themeColor: UIColor = NCAppBranding.themeColor()
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = themeColor
        appearance.titleTextAttributes = [.foregroundColor: NCAppBranding.themeTextColor()]
        self.navigationItem.standardAppearance = appearance
        self.navigationItem.compactAppearance = appearance
        self.navigationItem.scrollEdgeAppearance = appearance
        self.tableView.tableHeaderView = self.avatarHeaderView()
        self.showEditButton()
        self.getUserProfileEditableFields()
        let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId)
        showScopes = serverCapabilities.accountPropertyScopesVersion2
        modifyingProfileView = UIActivityIndicatorView()
        modifyingProfileView.color = NCAppBranding.themeTextColor()
        tableView.keyboardDismissMode = UIScrollView.KeyboardDismissMode.onDrag
        self.tableView.register(UINib(nibName: kTextInputTableViewCellNibName, bundle: nil), forCellReuseIdentifier: kTextInputCellIdentifier)
        NotificationCenter.default.addObserver(self, selector: #selector(userProfileImageUpdated), name: NSNotification.Name.NCUserProfileImageUpdated, object: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Workaround to fix label width
        guard let headerView = self.tableView.tableHeaderView as? AvatarHeaderView else {return}
        guard var labelFrame = headerView.nameLabel?.frame else {return}
        let padding: CGFloat = 16
        labelFrame.origin.x = padding
        labelFrame.size.width = self.tableView.bounds.size.width - padding * 2
        headerView.nameLabel?.frame = labelFrame
    }

    init(withAccount account: TalkAccount) {
        super.init(style: .grouped)
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
            ProfileSection.kProfileSectionAddAccount.rawValue:
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
            return textInputCellWith(text: account.userDisplayName, tag: kNameTextFieldTag, interactionEnabled: editableFields.contains(kUserProfileDisplayName),
                                     keyBoardType: nil, placeHolder: nil)
        case ProfileSection.kProfileSectionEmail.rawValue:
            return textInputCellWith(text: account.email, tag: kEmailTextFieldTag, interactionEnabled: editableFields.contains(kUserProfileEmail),
                                     keyBoardType: .emailAddress, placeHolder: NSLocalizedString("Your email address", comment: ""))
        case ProfileSection.kProfileSectionPhoneNumber.rawValue:
            let phoneNumber = try? phoneUtil.parse(account.phone, defaultRegion: nil)
            let text = (phoneNumber != nil) ? try? phoneUtil.format(phoneNumber, numberFormat: NBEPhoneNumberFormat.INTERNATIONAL) : nil
            return textInputCellWith(text: text, tag: kPhoneTextFieldTag, interactionEnabled: false,
                                     keyBoardType: .phonePad, placeHolder: NSLocalizedString("Your phone number", comment: ""))
        case ProfileSection.kProfileSectionAddress.rawValue:
            return textInputCellWith(text: account.address, tag: kAddressTextFieldTag, interactionEnabled: editableFields.contains(kUserProfileAddress),
                                     keyBoardType: nil, placeHolder: NSLocalizedString("Your postal address", comment: ""))
        case ProfileSection.kProfileSectionWebsite.rawValue:
            return textInputCellWith(text: account.website, tag: kWebsiteTextFieldTag, interactionEnabled: editableFields.contains(kUserProfileWebsite),
                                     keyBoardType: .URL, placeHolder: NSLocalizedString("Link https://…", comment: ""))
        case ProfileSection.kProfileSectionTwitter.rawValue:
            return textInputCellWith(text: account.twitter, tag: kTwitterTextFieldTag, interactionEnabled: editableFields.contains(kUserProfileTwitter),
                                     keyBoardType: .emailAddress, placeHolder: NSLocalizedString("Twitter handle @…", comment: ""))
        case ProfileSection.kProfileSectionSummary.rawValue:
            return summaryCellForRow(row: indexPath.row)
        case ProfileSection.kProfileSectionAddAccount.rawValue:
            return actionCellWith(identifier: "AddAccountCellIdentifier", text: NSLocalizedString("Add account", comment: ""),
                                  textColor: .systemBlue, image: UIImage(named: "add-action"), tintColor: .systemBlue)
        case ProfileSection.kProfileSectionRemoveAccount.rawValue:
            let actionTitle = multiAccountEnabled.boolValue ? NSLocalizedString("Remove account", comment: "") : NSLocalizedString("Log out", comment: "")
            let actionImage = multiAccountEnabled.boolValue ? UIImage(named: "delete") : UIImage(named: "logout")
            return actionCellWith(identifier: "RemoveAccountCellIdentifier", text: actionTitle, textColor: .systemRed, image: actionImage, tintColor: .systemRed)
        default:
            break
        }
        return UITableViewCell()
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let sections = getProfileSections()
        let section = sections[indexPath.section]
        if section == ProfileSection.kProfileSectionAddAccount.rawValue {
            self.addNewAccount()
        } else if section == ProfileSection.kProfileSectionRemoveAccount.rawValue {
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
        headerView.button.setImage(self.imageForScope(scope: scopeForImage), for: .normal)
    }

    func setupViewforHeaderInSection(profileSection: Int) -> HeaderWithButton {
        var headerView = HeaderWithButton()
        headerView.button.addTarget(self, action: #selector(showScopeSelectionDialog(_:)), for: .touchUpInside)
        let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId)
        let shouldEnableNameAndEmailScopeButton = serverCapabilities.accountPropertyScopesFederationEnabled

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

    func textInputCellWith(text: String?, tag: Int?, interactionEnabled: Bool?, keyBoardType: UIKeyboardType?, placeHolder: String?) -> TextInputTableViewCell {
        let textInputCell = tableView.dequeueReusableCell(withIdentifier: kTextInputCellIdentifier) as? TextInputTableViewCell ??
        TextInputTableViewCell(style: .default, reuseIdentifier: kTextInputCellIdentifier)

        textInputCell.textField.delegate = self

        if let text = text {
            textInputCell.textField.text = text
        }
        if let tag = tag {
            textInputCell.textField.tag = tag
        }
        if let interactionEnabled = interactionEnabled {
            textInputCell.textField.isUserInteractionEnabled = interactionEnabled
        }
        if let keyBoardType = keyBoardType {
            textInputCell.textField.keyboardType = keyBoardType
        }
        if let placeHolder = placeHolder {
            textInputCell.textField.placeholder = placeHolder
        }

        return textInputCell
    }

    func summaryCellForRow(row: Int) -> UITableViewCell {
        let summaryCell = tableView.dequeueReusableCell(withIdentifier: "SummaryCellIdentifier") ?? UITableViewCell(style: .default, reuseIdentifier: "SummaryCellIdentifier")
        let summaryRow = self.rowsInSummarySection()[row]
        switch summaryRow {
        case SummaryRow.kSummaryRowEmail.rawValue:
            summaryCell.textLabel?.text = account.email
            summaryCell.imageView?.image = UIImage(named: "mail")?.withRenderingMode(.alwaysTemplate)
        case SummaryRow.kSummaryRowPhoneNumber.rawValue:
            let phoneNumber = try? phoneUtil.parse(account.phone, defaultRegion: nil)
            let text = (phoneNumber != nil) ? try? phoneUtil.format(phoneNumber, numberFormat: NBEPhoneNumberFormat.INTERNATIONAL) : nil
            summaryCell.textLabel?.text = text
            summaryCell.imageView?.image = UIImage(named: "phone")?.withRenderingMode(.alwaysTemplate)
        case SummaryRow.kSummaryRowAddress.rawValue:
            summaryCell.textLabel?.text = account.address
            summaryCell.imageView?.image = UIImage(named: "location")?.withRenderingMode(.alwaysTemplate)
        case SummaryRow.kSummaryRowWebsite.rawValue:
            summaryCell.textLabel?.text = account.website
            summaryCell.imageView?.image = UIImage(named: "website")?.withRenderingMode(.alwaysTemplate)
        case SummaryRow.kSummaryRowTwitter.rawValue:
            summaryCell.textLabel?.text = account.twitter
            summaryCell.imageView?.image = UIImage(named: "twitter")?.withRenderingMode(.alwaysTemplate)
        default:
            break
        }

        summaryCell.imageView?.tintColor = UIColor(red: 0.43, green: 0.43, blue: 0.45, alpha: 1)

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
