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
    var phoneUtil: NBPhoneNumberUtil?
    var editableFields = NSArray()
    var showScopes: Bool?

    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationItem.title = NSLocalizedString("Profile", comment: "")
        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: NCAppBranding.themeTextColor()]
        self.navigationController?.navigationBar.tintColor = NCAppBranding.themeTextColor()
        self.navigationController?.navigationBar.barTintColor = NCAppBranding.themeColor()
        self.tabBarController?.tabBar.tintColor = NCAppBranding.themeColor()
        if #available(iOS 13.0, *) {
            let themeColor: UIColor = NCAppBranding.themeColor()
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = themeColor
            appearance.titleTextAttributes = [.foregroundColor: NCAppBranding.themeTextColor()]
            self.navigationItem.standardAppearance = appearance
            self.navigationItem.compactAppearance = appearance
            self.navigationItem.scrollEdgeAppearance = appearance
        }
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
        let headerView = self.tableView.tableHeaderView as? AvatarHeaderView
        guard let headerView = headerView else {
            return
        }
        var labelFrame = headerView.nameLabel?.frame
        let padding: CGFloat = 16
        labelFrame?.origin.x = padding
        labelFrame?.size.width = self.tableView.bounds.size.width - padding * 2
        if let labelFrame = labelFrame {
            headerView.nameLabel?.frame = labelFrame
        }
    }

    init(withAccount account: TalkAccount?) {
        super.init(style: .grouped)
        if let account = account {
            self.account = account
        }
        self.phoneUtil = NBPhoneNumberUtil()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Notifications

    @objc func userProfileImageUpdated(notification: NSNotification) {
        self.account = NCDatabaseManager.sharedInstance().activeAccount()
        self.refreshProfileTableView()
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
        let summaryCellIdentifier = "SummaryCellIdentifier"
        let addAccountCellIdentifier = "AddAccountCellIdentifier"
        let removeAccountCellIdentifier = "RemoveAccountCellIdentifier"
        var isTextInputCell = false
        var cell = UITableViewCell()
        var textInputCell = tableView.dequeueReusableCell(withIdentifier: kTextInputCellIdentifier) as? TextInputTableViewCell
        if textInputCell == nil {
            textInputCell = TextInputTableViewCell(style: .default, reuseIdentifier: kTextInputCellIdentifier)
        }
        textInputCell?.textField?.delegate = self
        textInputCell?.textField?.keyboardType = .default
        textInputCell?.textField?.placeholder = nil
        textInputCell?.textField?.autocorrectionType = .no
        let section = self.getProfileSections()[indexPath.section]
        switch section {
        case ProfileSection.kProfileSectionName.rawValue:
            setupTextInputCell(textInputCell: &textInputCell,
                               text: account.userDisplayName, tag: kNameTextFieldTag, interactionEnabled: editableFields.contains(kUserProfileDisplayName), keyBoardType: nil, placeHolder: nil)
            isTextInputCell = true
        case ProfileSection.kProfileSectionEmail.rawValue:
            setupTextInputCell(textInputCell: &textInputCell, text: account.email,
                               tag: kEmailTextFieldTag, interactionEnabled: editableFields.contains(kUserProfileEmail),
                               keyBoardType: .emailAddress, placeHolder: NSLocalizedString("Your email address", comment: ""))
            isTextInputCell = true
        case ProfileSection.kProfileSectionPhoneNumber.rawValue:
            let phoneNumber = try? phoneUtil?.parse(account.phone, defaultRegion: nil)
            let text = (phoneNumber != nil) ? try? phoneUtil?.format(phoneNumber, numberFormat: NBEPhoneNumberFormat.INTERNATIONAL) : nil
            setupTextInputCell(textInputCell: &textInputCell, text: text,
                               tag: kPhoneTextFieldTag, interactionEnabled: false,
                               keyBoardType: .phonePad, placeHolder: NSLocalizedString("Your phone number", comment: ""))
            isTextInputCell = true
        case ProfileSection.kProfileSectionAddress.rawValue:
            setupTextInputCell(textInputCell: &textInputCell, text: account.address,
                               tag: kAddressTextFieldTag, interactionEnabled: editableFields.contains(kUserProfileAddress),
                               keyBoardType: nil, placeHolder: NSLocalizedString("Your postal address", comment: ""))
            isTextInputCell = true
        case ProfileSection.kProfileSectionWebsite.rawValue:
            setupTextInputCell(textInputCell: &textInputCell, text: account.website,
                               tag: kWebsiteTextFieldTag, interactionEnabled: editableFields.contains(kUserProfileWebsite),
                               keyBoardType: .URL, placeHolder: NSLocalizedString("Link https://…", comment: ""))
            isTextInputCell = true
        case ProfileSection.kProfileSectionTwitter.rawValue:
            setupTextInputCell(textInputCell: &textInputCell, text: account.twitter,
                               tag: kTwitterTextFieldTag, interactionEnabled: editableFields.contains(kUserProfileTwitter),
                               keyBoardType: .emailAddress, placeHolder: NSLocalizedString("Twitter handle @…", comment: ""))
            isTextInputCell = true
        case ProfileSection.kProfileSectionSummary.rawValue:
            cell = UITableViewCell(style: .default, reuseIdentifier: summaryCellIdentifier)
            var scopeImage: UIImage?
            let summaryRow = self.rowsInSummarySection()[indexPath.row]
            switch summaryRow {
            case SummaryRow.kSummaryRowEmail.rawValue:
                setupSummaryRowCell(cell: &cell, scopeImage: &scopeImage, text: account.email, image: (UIImage(named: "mail")?.withRenderingMode(.alwaysTemplate)), scope: account.emailScope)
            case SummaryRow.kSummaryRowPhoneNumber.rawValue:
                let phoneNumber = try? phoneUtil?.parse(account.phone, defaultRegion: nil)
                let text = (phoneNumber != nil) ? try? phoneUtil?.format(phoneNumber, numberFormat: NBEPhoneNumberFormat.INTERNATIONAL) : nil
                setupSummaryRowCell(cell: &cell, scopeImage: &scopeImage, text: text, image: UIImage(named: "phone")?.withRenderingMode(.alwaysTemplate), scope: account.phoneScope)
            case SummaryRow.kSummaryRowAddress.rawValue:
                setupSummaryRowCell(cell: &cell, scopeImage: &scopeImage, text: account.address, image: UIImage(named: "location")?.withRenderingMode(.alwaysTemplate), scope: account.addressScope)
            case SummaryRow.kSummaryRowWebsite.rawValue:
                setupSummaryRowCell(cell: &cell, scopeImage: &scopeImage, text: account.website, image: UIImage(named: "website")?.withRenderingMode(.alwaysTemplate), scope: account.websiteScope)
            case SummaryRow.kSummaryRowTwitter.rawValue:
                setupSummaryRowCell(cell: &cell, scopeImage: &scopeImage, text: account.twitter, image: UIImage(named: "twitter")?.withRenderingMode(.alwaysTemplate), scope: account.twitterScope)
            default:
                break
            }
            cell.imageView?.tintColor = UIColor(red: 0.43, green: 0.43, blue: 0.45, alpha: 1)

            if showScopes ?? false {
                let scopeImageView = UIImageView(image: scopeImage)
                scopeImageView.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
                scopeImageView.tintColor = NCAppBranding.placeholderColor()
            }
        case ProfileSection.kProfileSectionAddAccount.rawValue:
            cell = UITableViewCell(style: .default, reuseIdentifier: addAccountCellIdentifier)
            setupAddRemoveAccountCell(cell: &cell, text: NSLocalizedString("Add account", comment: ""), textColor: .systemBlue, image: UIImage(named: "add-action"), tintColor: .systemBlue)
        case ProfileSection.kProfileSectionRemoveAccount.rawValue:
            cell = UITableViewCell(style: .default, reuseIdentifier: removeAccountCellIdentifier)
            let actionTitle = multiAccountEnabled.boolValue ? NSLocalizedString("Remove account", comment: "") : NSLocalizedString("Log out", comment: "")
            let actionImage = multiAccountEnabled.boolValue ? UIImage(named: "delete") : UIImage(named: "logout")
            setupAddRemoveAccountCell(cell: &cell, text: actionTitle, textColor: .systemRed, image: actionImage, tintColor: .systemRed)
        default:
            break
        }
        if isTextInputCell {
            if let textInputCell = textInputCell {
                cell = textInputCell
            }
        }
        return cell
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
            setupViewForSection(headerView: &headerView, title: NSLocalizedString("Full name", comment: ""), buttonTag:
                                        kNameTextFieldTag, enabled: shouldEnableNameAndEmailScopeButton, scopeForImage: account.userDisplayNameScope)
        case ProfileSection.kProfileSectionEmail.rawValue:
            setupViewForSection(headerView: &headerView, title: NSLocalizedString("Email", comment: ""), buttonTag: kEmailTextFieldTag,
                                       enabled: shouldEnableNameAndEmailScopeButton, scopeForImage: account.emailScope)
        case ProfileSection.kProfileSectionPhoneNumber.rawValue:
            setupViewForSection(headerView: &headerView, title: NSLocalizedString("Phone number", comment: ""), buttonTag: kPhoneTextFieldTag, enabled: nil, scopeForImage: account.phoneScope)
        case ProfileSection.kProfileSectionAddress.rawValue:
            setupViewForSection(headerView: &headerView, title: NSLocalizedString("Address", comment: ""), buttonTag: kAddressTextFieldTag, enabled: nil, scopeForImage: account.addressScope)
        case ProfileSection.kProfileSectionWebsite.rawValue:
            setupViewForSection(headerView: &headerView, title: NSLocalizedString("Website", comment: ""), buttonTag: kWebsiteTextFieldTag, enabled: nil, scopeForImage: account.websiteScope)
        case ProfileSection.kProfileSectionTwitter.rawValue:
            setupViewForSection(headerView: &headerView, title: NSLocalizedString("Twitter", comment: ""), buttonTag: kTwitterTextFieldTag, enabled: nil, scopeForImage: account.twitterScope)
        default:
            break
        }
        return headerView
    }

    // MARK: Setup cells

    func setupTextInputCell(textInputCell: inout TextInputTableViewCell?, text: String?, tag: Int?, interactionEnabled: Bool?, keyBoardType: UIKeyboardType?, placeHolder: String?) {
        guard let textInputCell = textInputCell else {
            return
        }
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
    }

    func setupSummaryRowCell(cell: inout UITableViewCell, scopeImage: inout UIImage?, text: String?, image: UIImage?, scope: String) {
        if let text = text {
            cell.textLabel?.text = text
        }
        cell.imageView?.image = image
        scopeImage = self.imageForScope(scope: scope)
    }

    func setupAddRemoveAccountCell(cell: inout UITableViewCell, text: String, textColor: UIColor, image: UIImage?, tintColor: UIColor) {
        cell.textLabel?.text = text
        cell.textLabel?.textColor = textColor
        cell.imageView?.image = image?.withRenderingMode(.alwaysTemplate)
        cell.imageView?.tintColor = tintColor
    }
}
