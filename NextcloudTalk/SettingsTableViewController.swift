//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import NextcloudKit
import SafariServices
import SwiftUI
import ReplayKit
import SDWebImage
import libPhoneNumber

enum SettingsSection: Int {
    case kSettingsSectionUser = 0
    case kSettingsSectionUserStatus
    case kSettingsSectionAccountSettings
    case kSettingsSectionOtherAccounts
    case kSettingsSectionConfiguration
    case kSettingsSectionAdvanced
    case kSettingsSectionAbout
}

enum AccountSettingsOptions: Int {
    case kAccountSettingsReadStatusPrivacy = 0
    case kAccountSettingsTypingPrivacy
    case kAccountSettingsContactsSync
}

enum ConfigurationSectionOption: Int {
    case kConfigurationSectionOptionVideo = 0
    case kConfigurationSectionOptionRecents
}

enum AdvancedSectionOption: Int {
    case kAdvancedSectionOptionDiagnostics = 0
    case kAdvancedSectionOptionCachedImages
    case kAdvancedSectionOptionCachedFiles
    case kAdvancedSectionOptionCallFromOldAccount
}

enum AboutSection: Int {
    case kAboutSectionPrivacy = 0
    case kAboutSectionSourceCode
}

class SettingsTableViewController: UITableViewController, UITextFieldDelegate, UserStatusViewDelegate, CallsFromOldAccountViewControllerDelegate {
    let kPhoneTextFieldTag = 99

    let iconConfiguration = UIImage.SymbolConfiguration(pointSize: 18)

    var activeUserStatus: NCUserStatus?
    var readStatusSwitch = UISwitch()
    var typingIndicatorSwitch = UISwitch()
    var contactSyncSwitch = UISwitch()
    var setPhoneAction: UIAlertAction?
    var includeInRecentsSwitch = UISwitch()

    var totalImageCacheSize = 0
    var totalFileCacheSize = 0

    var activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
    var inactiveAccounts = NCDatabaseManager.sharedInstance().inactiveAccounts()
    var serverCapabilities: ServerCapabilities? {
        // Since NCDatabaseManager already caches the capabilities, we don't need a lazy var here
        NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId)
    }

    lazy var profilePictures: [String: UIImage] = {
        var result: [String: UIImage] = [:]

        for account in NCDatabaseManager.sharedInstance().allAccounts() {
            guard let account = account as? TalkAccount else {
                continue
            }

            if let image = NCAPIController.sharedInstance().userProfileImage(for: account, with: self.traitCollection.userInterfaceStyle) {
                result[account.accountId] = image
            }
        }

        return result
    }()

    @IBOutlet weak var cancelButton: UIBarButtonItem!

    override func viewDidLoad() {
        super.viewDidLoad()

        NCAppBranding.styleViewController(self)

        self.navigationItem.title = NSLocalizedString("Settings", comment: "")

        if #unavailable(iOS 26.0) {
            self.cancelButton.tintColor = NCAppBranding.themeTextColor()
        }

        contactSyncSwitch.frame = .zero
        contactSyncSwitch.addTarget(self, action: #selector(contactSyncValueChanged(_:)), for: .valueChanged)

        readStatusSwitch.frame = .zero
        readStatusSwitch.addTarget(self, action: #selector(readStatusValueChanged(_:)), for: .valueChanged)

        includeInRecentsSwitch.frame = .zero
        includeInRecentsSwitch.addTarget(self, action: #selector(includeInRecentsValueChanged(_:)), for: .valueChanged)

        typingIndicatorSwitch.frame = .zero
        typingIndicatorSwitch.addTarget(self, action: #selector(typingIndicatorValueChanged(_:)), for: .valueChanged)

        NotificationCenter.default.addObserver(self, selector: #selector(appStateHasChanged(notification:)), name: NSNotification.Name.NCAppStateHasChangedNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(contactsHaveBeenUpdated(notification:)), name: NSNotification.Name.NCContactsManagerContactsUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(contactsAccessHasBeenUpdated(notification:)), name: NSNotification.Name.NCContactsManagerContactsAccessUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(userProfileImageUpdated), name: NSNotification.Name.NCUserProfileImageUpdated, object: nil)

        self.updateTotalImageCacheSize()
        self.updateTotalFileCacheSize()

        self.adaptInterfaceForAppState(appState: NCConnectionController.shared.appState)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    @IBAction func cancelButtonPressed(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
    }

    func getSettingsSections() -> [Int] {
        var sections = [Int]()

        // Active user section
        sections.append(SettingsSection.kSettingsSectionUser.rawValue)

        // User status section
        if serverCapabilities?.userStatus ?? false {
            sections.append(SettingsSection.kSettingsSectionUserStatus.rawValue)
        }

        // Account settings section
        sections.append(SettingsSection.kSettingsSectionAccountSettings.rawValue)

        // Other accounts section
        if !inactiveAccounts.isEmpty {
            sections.append(SettingsSection.kSettingsSectionOtherAccounts.rawValue)
        }

        // Configuration section
        sections.append(SettingsSection.kSettingsSectionConfiguration.rawValue)

        // Advanced section
        sections.append(SettingsSection.kSettingsSectionAdvanced.rawValue)

        // About section
        sections.append(SettingsSection.kSettingsSectionAbout.rawValue)
        return sections
    }

    func getAccountSettingsSectionOptions() -> [Int] {
        var options = [Int]()

        // Read status privacy setting
        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityChatReadStatus) {
            options.append(AccountSettingsOptions.kAccountSettingsReadStatusPrivacy.rawValue)
        }

        // Typing indicator privacy setting
        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityTypingIndicators) {
            options.append(AccountSettingsOptions.kAccountSettingsTypingPrivacy.rawValue)
        }

        // Contacts sync
        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityPhonebookSearch) {
            options.append(AccountSettingsOptions.kAccountSettingsContactsSync.rawValue)
        }
        return options
    }

    func getConfigurationSectionOptions() -> [Int] {
        var options = [Int]()

        // Video quality
        options.append(ConfigurationSectionOption.kConfigurationSectionOptionVideo.rawValue)

        // Calls in recents
        options.append(ConfigurationSectionOption.kConfigurationSectionOptionRecents.rawValue)

        return options
    }

    func getAdvancedSectionOptions() -> [Int] {
        var options = [Int]()

        // Diagnostics
        options.append(AdvancedSectionOption.kAdvancedSectionOptionDiagnostics.rawValue)

        // Caches
        options.append(AdvancedSectionOption.kAdvancedSectionOptionCachedImages.rawValue)
        options.append(AdvancedSectionOption.kAdvancedSectionOptionCachedFiles.rawValue)

        // Received calls from old accounts
        if NCSettingsController.sharedInstance().didReceiveCallsFromOldAccount() {
            options.append(AdvancedSectionOption.kAdvancedSectionOptionCallFromOldAccount.rawValue)
        }

        return options
    }

    func getAboutSectionOptions() -> [Int] {
        var options = [Int]()

        // Privacy
        options.append(AboutSection.kAboutSectionPrivacy.rawValue)

        // Source code
        if !isBrandedApp.boolValue {
            options.append(AboutSection.kAboutSectionSourceCode.rawValue)
        }

        return options
    }

    func getSectionForSettingsSection(section: SettingsSection) -> Int {
        let section = getSettingsSections().firstIndex(of: section.rawValue)
        return section ?? 0
    }

    func getIndexPathForConfigurationOption(option: ConfigurationSectionOption) -> IndexPath {
        let section = getSectionForSettingsSection(section: SettingsSection.kSettingsSectionConfiguration)
        let row = getConfigurationSectionOptions().firstIndex(of: option.rawValue)
        return IndexPath(row: row ?? 0, section: section)
    }

    // MARK: - User Profile

    func refreshUserProfile() {
        NCSettingsController.sharedInstance().getUserProfile(forAccountId: activeAccount.accountId) { _ in
            self.tableView.reloadData()
        }
        self.getActiveUserStatus()
    }

    func getActiveUserStatus() {
        NCAPIController.sharedInstance().getUserStatus(for: activeAccount) { userStatus, error in
            if let userStatus = userStatus, error == nil {
                self.activeUserStatus = NCUserStatus(dictionary: userStatus)
                self.tableView.reloadData()
            }
        }
    }

    // MARK: - Notifications

    @objc func appStateHasChanged(notification: NSNotification) {
        let appState = notification.userInfo?["appState"]
        if let rawAppState = appState as? Int, let appState = AppState(rawValue: rawAppState) {
            self.adaptInterfaceForAppState(appState: appState)
        }
    }

    @objc func contactsHaveBeenUpdated(notification: NSNotification) {
        DispatchQueue.main.async {
            self.activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
            self.tableView.reloadData()
        }
    }

    @objc func contactsAccessHasBeenUpdated(notification: NSNotification) {
        DispatchQueue.main.async {
            self.activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
            self.tableView.reloadData()
        }
    }

    @objc func userProfileImageUpdated(notification: NSNotification) {
        self.tableView.reloadSections(IndexSet(integer: SettingsSection.kSettingsSectionUser.rawValue), with: .none)
    }

    // MARK: - User Interface

    func adaptInterfaceForAppState(appState: AppState) {
        switch appState {
        case .ready:
            refreshUserProfile()
        default:
            break
        }
    }

    // MARK: - Profile actions

    func userProfilePressed() {
        let userProfileVC = UserProfileTableViewController(withAccount: activeAccount)
        self.navigationController?.pushViewController(userProfileVC, animated: true)
    }

    // MARK: - User Status (SwiftUI)

    func presentUserStatusOptions() {
        if let activeUserStatus = activeUserStatus {
            var userStatusView = UserStatusSwiftUIView(userStatus: activeUserStatus)
            userStatusView.delegate = self
            let hostingController = UIHostingController(rootView: userStatusView)
            self.present(hostingController, animated: true)
        }
    }

    func userStatusViewDidDisappear() {
        self.getActiveUserStatus()
    }

    // MARK: - User phone number

    func checkUserPhoneNumber() {
        NCSettingsController.sharedInstance().getUserProfile(forAccountId: activeAccount.accountId) { _ in
            if self.activeAccount.phone.isEmpty {
                self.presentSetPhoneNumberDialog()
            }
        }
    }

    func presentSetPhoneNumberDialog() {
        let alertTitle = NSLocalizedString("Phone number", comment: "")
        let alertMessage = NSLocalizedString("You can set your phone number so other users will be able to find you", comment: "")
        let setPhoneNumberDialog = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: .alert)

        setPhoneNumberDialog.addTextField { [self] textField in
            let location = NSLocale.current.regionCode
            let countryCode = NBPhoneNumberUtil.sharedInstance().getCountryCode(forRegion: location)
            if let countryCode = countryCode {
                textField.text = "+\(countryCode)"
            }
            if let exampleNumber = try? NBPhoneNumberUtil.sharedInstance().getExampleNumber(location) {
                textField.placeholder = try? NBPhoneNumberUtil.sharedInstance().format(exampleNumber, numberFormat: NBEPhoneNumberFormat.INTERNATIONAL)
            }
            textField.keyboardType = .phonePad
            textField.delegate = self
            textField.tag = kPhoneTextFieldTag
        }
        setPhoneAction = UIAlertAction(title: NSLocalizedString("Set", comment: ""), style: .default, handler: { _ in
            let phoneNumber = setPhoneNumberDialog.textFields?[0].text

            NCAPIController.sharedInstance().setUserProfileField(kUserProfilePhone, withValue: phoneNumber, for: self.activeAccount) { error, _ in
                if error != nil {
                    if let phoneNumber = phoneNumber {
                        self.presentPhoneNumberErrorDialog(phoneNumber: phoneNumber)
                    }
                    print("Error setting phone number ", error ?? "")
                } else {
                    NotificationPresenter.shared().present(text: NSLocalizedString("Phone number set successfully", comment: ""), dismissAfterDelay: 5.0, includedStyle: .success)
                }
                self.refreshUserProfile()
            }
        })
        if let setPhoneAction = setPhoneAction {
            setPhoneAction.isEnabled = false
            setPhoneNumberDialog.addAction(setPhoneAction)
        }
        let cancelAction = UIAlertAction(title: NSLocalizedString("Skip", comment: ""), style: .default) { _ in
            self.refreshUserProfile()
        }
        setPhoneNumberDialog.addAction(cancelAction)
        self.present(setPhoneNumberDialog, animated: true, completion: nil)
    }

    func presentPhoneNumberErrorDialog(phoneNumber: String) {
        let alertTitle = NSLocalizedString("Could not set phone number", comment: "")
        var alertMessage = NSLocalizedString("An error occurred while setting phone number", comment: "")
        let failedPhoneNumber = try? NBPhoneNumberUtil.sharedInstance().parse(phoneNumber, defaultRegion: nil)
        if let formattedPhoneNumber = try? NBPhoneNumberUtil.sharedInstance().format(failedPhoneNumber, numberFormat: NBEPhoneNumberFormat.INTERNATIONAL) {
            alertMessage = NSLocalizedString("An error occurred while setting \(formattedPhoneNumber) as phone number", comment: "")
        }

        let failedPhoneNumberDialog = UIAlertController(
            title: alertTitle,
            message: alertMessage,
            preferredStyle: .alert)

        let retryAction = UIAlertAction(title: NSLocalizedString("Retry", comment: ""), style: .default) { _ in
            self.presentSetPhoneNumberDialog()
        }
        failedPhoneNumberDialog.addAction(retryAction)

        let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil)
        failedPhoneNumberDialog.addAction(cancelAction)

        self.present(failedPhoneNumberDialog, animated: true, completion: nil)
    }

    // MARK: UITextField delegate

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if textField.tag == kPhoneTextFieldTag {
            let inputPhoneNumber = (textField.text as NSString?)?.replacingCharacters(in: range, with: string)
            let phoneNumber = try? NBPhoneNumberUtil.sharedInstance().parse(inputPhoneNumber, defaultRegion: nil)
            setPhoneAction?.isEnabled = NBPhoneNumberUtil.sharedInstance().isValidNumber(phoneNumber)
        }
        return true
    }

    // MARK: - Configuration

    func presentVideoResoultionsSelector() {
        let videoConfIndexPath = self.getIndexPathForConfigurationOption(option: ConfigurationSectionOption.kConfigurationSectionOptionVideo)
        let videoResolutions = NCSettingsController.sharedInstance().videoSettingsModel.availableVideoResolutions()
        let storedResolution = NCSettingsController.sharedInstance().videoSettingsModel.currentVideoResolutionSettingFromStore()

        let optionsActionSheet = UIAlertController(title: NSLocalizedString("Video quality", comment: ""), message: nil, preferredStyle: .actionSheet)

        for resolution in videoResolutions {
            let readableResolution = NCSettingsController.sharedInstance().videoSettingsModel.readableResolution(resolution)
            let isStoredResolution = resolution == storedResolution
            let action = UIAlertAction(title: readableResolution, style: .default) { _ in
                NCSettingsController.sharedInstance().videoSettingsModel.storeVideoResolutionSetting(resolution)
                self.tableView.beginUpdates()
                self.tableView.reloadRows(at: [videoConfIndexPath], with: .none)
                self.tableView.endUpdates()
            }

            if isStoredResolution {
                action.setValue(UIImage(named: "checkmark")?.withRenderingMode(_: .alwaysOriginal), forKey: "image")
            }
            optionsActionSheet.addAction(action)
        }

        optionsActionSheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))

        // Presentation on iPads
        optionsActionSheet.popoverPresentationController?.sourceView = self.tableView
        optionsActionSheet.popoverPresentationController?.sourceRect = self.tableView.rectForRow(at: videoConfIndexPath)

        self.present(optionsActionSheet, animated: true, completion: nil)
    }

    @objc func contactSyncValueChanged(_ sender: Any?) {
        NCSettingsController.sharedInstance().setContactSync(contactSyncSwitch.isOn)
        if contactSyncSwitch.isOn {
            if !NCContactsManager.sharedInstance().isContactAccessDetermined() {
                NCContactsManager.sharedInstance().requestContactsAccess { granted in
                    if granted {
                        self.checkUserPhoneNumber()
                        NCContactsManager.sharedInstance().searchInServer(forAddressBookContacts: true)
                    }
                }
            } else if NCContactsManager.sharedInstance().isContactAccessAuthorized() {
                self.checkUserPhoneNumber()
                NCContactsManager.sharedInstance().searchInServer(forAddressBookContacts: true)
            }
        } else {
            NCContactsManager.sharedInstance().removeStoredContacts()
        }
        // Reload to update configuration section footer
        self.tableView.reloadData()
    }

    @objc func readStatusValueChanged(_ sender: Any?) {
        readStatusSwitch.isEnabled = false

        NCAPIController.sharedInstance().setReadStatusPrivacySettingEnabled(!readStatusSwitch.isOn, for: activeAccount) { error in
            if error == nil {
                NCSettingsController.sharedInstance().getCapabilitiesForAccountId(self.activeAccount.accountId) { error in
                    if error == nil {
                        self.readStatusSwitch.isEnabled = true
                        self.tableView.reloadData()
                    } else {
                        self.showReadStatusModificationError()
                    }
                }
            } else {
                self.showReadStatusModificationError()
            }
        }
    }

    func showReadStatusModificationError() {
        readStatusSwitch.isEnabled = true
        self.tableView.reloadData()
        let errorDialog = UIAlertController(
            title: NSLocalizedString("An error occurred changing read status setting", comment: ""),
            message: nil,
            preferredStyle: .alert)
        let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil)
        errorDialog.addAction(okAction)
        self.present(errorDialog, animated: true, completion: nil)
    }

    @objc func typingIndicatorValueChanged(_ sender: Any?) {
        typingIndicatorSwitch.isEnabled = false

        NCAPIController.sharedInstance().setTypingPrivacySettingEnabled(!typingIndicatorSwitch.isOn, for: activeAccount) { error in
            if error == nil {
                NCSettingsController.sharedInstance().getCapabilitiesForAccountId(self.activeAccount.accountId) { error in
                    if error == nil {
                        self.typingIndicatorSwitch.isEnabled = true
                        self.tableView.reloadData()
                    } else {
                        self.showTypeIndicatorModificationError()
                    }
                }
            } else {
                self.showTypeIndicatorModificationError()
            }
        }
    }

    func showTypeIndicatorModificationError() {
        self.typingIndicatorSwitch.isEnabled = true
        self.tableView.reloadData()
        let errorDialog = UIAlertController(
            title: NSLocalizedString("An error occurred changing typing privacy setting", comment: ""),
            message: nil,
            preferredStyle: .alert)
        let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil)
        errorDialog.addAction(okAction)
        self.present(errorDialog, animated: true, completion: nil)
    }

    @objc func includeInRecentsValueChanged(_ sender: Any?) {
        NCUserDefaults.setIncludeCallsInRecentsEnabled(includeInRecentsSwitch.isOn)
        CallKitManager.sharedInstance().setDefaultProviderConfiguration()
    }

    // MARK: - Advanced actions

    func diagnosticsPressed() {
        let diagnosticsVC = DiagnosticsTableViewController(withAccount: activeAccount)

        self.navigationController?.pushViewController(diagnosticsVC, animated: true)
    }

    func cachedImagesPressed() {
        let clearCacheDialog = UIAlertController(
            title: NSLocalizedString("Clear cache", comment: ""),
            message: NSLocalizedString("Do you really want to clear the image cache?", comment: ""),
            preferredStyle: .alert)

        let clearAction = UIAlertAction(title: NSLocalizedString("Clear cache", comment: ""), style: .destructive) { _ in
            URLCache.shared.removeAllCachedResponses()
            SDImageCache.shared.clearMemory()
            SDImageCache.shared.clearDisk {
                self.updateTotalImageCacheSize()
                self.tableView.reloadData()
            }
        }
        clearCacheDialog.addAction(clearAction)

        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
        clearCacheDialog.addAction(cancelAction)

        self.present(clearCacheDialog, animated: true, completion: nil)
    }

    func cachedFilesPressed() {
        let clearCacheDialog = UIAlertController(
            title: NSLocalizedString("Clear cache", comment: ""),
            message: NSLocalizedString("Do you really want to clear the file cache?", comment: ""),
            preferredStyle: .alert)

        let clearAction = UIAlertAction(title: NSLocalizedString("Clear cache", comment: ""), style: .destructive) { _ in
            let fileController = NCChatFileController()
            let talkAccounts = NCDatabaseManager.sharedInstance().allAccounts()

            if let talkAccounts = talkAccounts as? [TalkAccount] {
                for account in talkAccounts {
                    fileController.clearDownloadDirectory(for: account)
                }
            }

            self.updateTotalFileCacheSize()
            self.tableView.reloadData()
        }
        clearCacheDialog.addAction(clearAction)

        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
        clearCacheDialog.addAction(cancelAction)

        self.present(clearCacheDialog, animated: true, completion: nil)
    }

    func callsFromOldAccountPressed() {
        let vc = CallsFromOldAccountViewController()
        vc.delegate = self

        self.navigationController?.pushViewController(vc, animated: true)
    }

    func callsFromOldAccountWarningAcknowledged() {
        self.tableView.reloadData()
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return getSettingsSections().count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sections = getSettingsSections()
        let settingsSection = sections[section]

        switch settingsSection {
        case SettingsSection.kSettingsSectionUser.rawValue:
            return 1
        case SettingsSection.kSettingsSectionUserStatus.rawValue:
            return 1
        case SettingsSection.kSettingsSectionAccountSettings.rawValue:
            return getAccountSettingsSectionOptions().count
        case SettingsSection.kSettingsSectionConfiguration.rawValue:
            return getConfigurationSectionOptions().count
        case SettingsSection.kSettingsSectionAdvanced.rawValue:
            return getAdvancedSectionOptions().count
        case SettingsSection.kSettingsSectionAbout.rawValue:
            return getAboutSectionOptions().count
        case SettingsSection.kSettingsSectionOtherAccounts.rawValue:
            return inactiveAccounts.count
        default:
            break
        }
        return 1
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let sections = getSettingsSections()
        let settingsSection = sections[section]

        switch settingsSection {
        case SettingsSection.kSettingsSectionOtherAccounts.rawValue:
            return NSLocalizedString("Other Accounts", comment: "")
        case SettingsSection.kSettingsSectionConfiguration.rawValue:
            return NSLocalizedString("Configuration", comment: "")
        case SettingsSection.kSettingsSectionAdvanced.rawValue:
            return NSLocalizedString("Advanced", comment: "")
        case SettingsSection.kSettingsSectionAbout.rawValue:
            return NSLocalizedString("About", comment: "")
        default:
            break
        }
        return nil
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        let sections = getSettingsSections()
        let settingsSection = sections[section]

        if settingsSection == SettingsSection.kSettingsSectionAbout.rawValue {
            let appName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)!

            return "\(appName) \(NCAppBranding.getAppVersionString())\n\(copyright)"
        }

        if settingsSection == SettingsSection.kSettingsSectionAccountSettings.rawValue && contactSyncSwitch.isOn {
            if NCContactsManager.sharedInstance().isContactAccessDetermined() && !NCContactsManager.sharedInstance().isContactAccessAuthorized() {
                return NSLocalizedString("Contact access has been denied", comment: "")
            }
            if activeAccount.lastContactSync > 0 {
                let lastUpdate = Date(timeIntervalSince1970: TimeInterval(activeAccount.lastContactSync))
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                dateFormatter.timeStyle = .short
                return NSLocalizedString("Last sync", comment: "") + ": " + dateFormatter.string(from: lastUpdate)
            }
        }

        if settingsSection == SettingsSection.kSettingsSectionUser.rawValue && contactSyncSwitch.isOn {
            if activeAccount.phone.isEmpty {
                let missingPhoneString = NSLocalizedString("Missing phone number information", comment: "")
                return "⚠ " + missingPhoneString
            }
        }
        return nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let sections = getSettingsSections()
        let settingsSection = sections[indexPath.section]

        switch settingsSection {
        case SettingsSection.kSettingsSectionUser.rawValue:
            let cell: SettingsTableViewCell = tableView.dequeueOrCreateCell(withIdentifier: "UserProfileCellIdentifier", style: .subtitle)
            cell.textLabel?.text = activeAccount.userDisplayName
            cell.textLabel?.font = .preferredFont(for: .title2, weight: .medium)
            cell.detailTextLabel?.text = activeAccount.server.replacingOccurrences(of: "https://", with: "")
            cell.detailTextLabel?.lineBreakMode = .byCharWrapping
            cell.imageView?.image = self.getProfilePicture(for: activeAccount)?.cropToCircle(withSize: CGSize(width: 60, height: 60))
            cell.accessoryType = .disclosureIndicator
            return cell

        case SettingsSection.kSettingsSectionUserStatus.rawValue:
            let cell: SettingsTableViewCell = tableView.dequeueOrCreateCell(withIdentifier: "UserStatusCellIdentifier", style: .subtitle)
            if activeUserStatus != nil {
                cell.textLabel?.text = activeUserStatus!.readableUserStatus()
                let statusMessage = activeUserStatus!.readableUserStatusMessage()
                if !statusMessage.isEmpty {
                    cell.textLabel?.text = statusMessage
                }
                if activeUserStatus!.status == kUserStatusDND {
                    cell.detailTextLabel?.text = NSLocalizedString("All notifications are muted", comment: "")
                }
                let statusImage = activeUserStatus!.getSFUserStatusIcon()
                cell.imageView?.image = statusImage
            } else {
                cell.textLabel?.text = NSLocalizedString("Fetching status …", comment: "")
            }
            return cell

        case SettingsSection.kSettingsSectionAccountSettings.rawValue:
            return userSettingsCell(for: indexPath)

        case SettingsSection.kSettingsSectionOtherAccounts.rawValue:
            return userAccountsCell(for: indexPath)

        case SettingsSection.kSettingsSectionConfiguration.rawValue:
            return sectionConfigurationCell(for: indexPath)

        case SettingsSection.kSettingsSectionAdvanced.rawValue:
            return advancedCell(for: indexPath)

        case SettingsSection.kSettingsSectionAbout.rawValue:
            return sectionAboutCell(for: indexPath)

        default:
            return UITableViewCell()
        }
    }

    func didSelectOtherAccountSectionCell(for indexPath: IndexPath) {
        if let account = inactiveAccounts[indexPath.row] as? TalkAccount {
            NCSettingsController.sharedInstance().setActiveAccountWithAccountId(account.accountId)
        }
    }

    func didSelectAccountSettingsSectionCell(for indexPath: IndexPath) {
        let options = getAccountSettingsSectionOptions()
        let option = options[indexPath.row]
        switch option {
        case AccountSettingsOptions.kAccountSettingsContactsSync.rawValue:
            NCContactsManager.sharedInstance().searchInServer(forAddressBookContacts: true)
        default:
            break
        }
    }

    func didSelectSettingsSectionCell(for indexPath: IndexPath) {
        let options = getConfigurationSectionOptions()
        let option = options[indexPath.row]
        switch option {
        case ConfigurationSectionOption.kConfigurationSectionOptionVideo.rawValue:
            self.presentVideoResoultionsSelector()
        default:
            break
        }
    }

    func didSelectAdvancedSectionCell(for indexPath: IndexPath) {
        let options = getAdvancedSectionOptions()
        let option = options[indexPath.row]
        switch option {
        case AdvancedSectionOption.kAdvancedSectionOptionDiagnostics.rawValue:
            self.diagnosticsPressed()
        case AdvancedSectionOption.kAdvancedSectionOptionCachedImages.rawValue:
            self.cachedImagesPressed()
        case AdvancedSectionOption.kAdvancedSectionOptionCachedFiles.rawValue:
            self.cachedFilesPressed()
        case AdvancedSectionOption.kAdvancedSectionOptionCallFromOldAccount.rawValue:
            self.callsFromOldAccountPressed()
        default:
            break
        }
    }

    func didSelectAboutSectionCell(for indexPath: IndexPath) {
        let options = getAboutSectionOptions()
        let option = options[indexPath.row]
        switch option {
        case AboutSection.kAboutSectionPrivacy.rawValue:
            if let url = URL(string: privacyURL), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                let safariVC = SFSafariViewController(url: url)
                self.present(safariVC, animated: true, completion: nil)
            }
        case AboutSection.kAboutSectionSourceCode.rawValue:
            let safariVC = SFSafariViewController(url: URL(string: "https://github.com/nextcloud/talk-ios")!)
            self.present(safariVC, animated: true, completion: nil)
        default:
            break
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let sections = getSettingsSections()
        let settingsSection = sections[indexPath.section]
        switch settingsSection {
        case SettingsSection.kSettingsSectionUser.rawValue:
            self.userProfilePressed()

        case SettingsSection.kSettingsSectionUserStatus.rawValue:
            self.presentUserStatusOptions()

        case SettingsSection.kSettingsSectionAccountSettings.rawValue:
            self.didSelectAccountSettingsSectionCell(for: indexPath)

        case SettingsSection.kSettingsSectionOtherAccounts.rawValue:
            self.didSelectOtherAccountSectionCell(for: indexPath)

        case SettingsSection.kSettingsSectionConfiguration.rawValue:
            self.didSelectSettingsSectionCell(for: indexPath)

        case SettingsSection.kSettingsSectionAdvanced.rawValue:
            self.didSelectAdvancedSectionCell(for: indexPath)

        case SettingsSection.kSettingsSectionAbout.rawValue:
            didSelectAboutSectionCell(for: indexPath)

        default:
            break
        }
        self.tableView.deselectRow(at: indexPath, animated: true)
    }
}

extension SettingsTableViewController {

    func userSettingsCell(for indexPath: IndexPath) -> UITableViewCell {
        let userSettingsCellIdentifier = "UserSettingsCellIdentifier"

        let options = getAccountSettingsSectionOptions()
        let option = options[indexPath.row]

        switch option {
        case AccountSettingsOptions.kAccountSettingsReadStatusPrivacy.rawValue:
            let cell: SettingsTableViewCell = tableView.dequeueOrCreateCell(withIdentifier: userSettingsCellIdentifier, style: .subtitle)
            cell.textLabel?.text = NSLocalizedString("Read status", comment: "")
            cell.setSettingsImage(image: UIImage(named: "check-all"))
            cell.accessoryView = readStatusSwitch
            readStatusSwitch.isOn = !(serverCapabilities?.readStatusPrivacy ?? true)
            cell.selectionStyle = .none
            return cell

        case AccountSettingsOptions.kAccountSettingsTypingPrivacy.rawValue:
            let cell: SettingsTableViewCell = tableView.dequeueOrCreateCell(withIdentifier: userSettingsCellIdentifier, style: .subtitle)
            cell.textLabel?.text = NSLocalizedString("Typing indicator", comment: "")
            cell.setSettingsImage(image: UIImage(systemName: "rectangle.and.pencil.and.ellipsis")?.applyingSymbolConfiguration(iconConfiguration))
            cell.accessoryView = typingIndicatorSwitch
            typingIndicatorSwitch.isOn = !(serverCapabilities?.typingPrivacy ?? true)
            cell.selectionStyle = .none

            let externalSignalingController = NCSettingsController.sharedInstance().externalSignalingController(forAccountId: activeAccount.accountId)
            if externalSignalingController == nil {
                cell.detailTextLabel?.text = NSLocalizedString("Typing indicators are only available when using a high performance backend (HPB)",
                                                               comment: "")
            }

            return cell

        case AccountSettingsOptions.kAccountSettingsContactsSync.rawValue:
            let cell: SettingsTableViewCell = tableView.dequeueOrCreateCell(withIdentifier: userSettingsCellIdentifier, style: .subtitle)
            cell.textLabel?.text = NSLocalizedString("Phone number integration", comment: "")
            cell.detailTextLabel?.text = NSLocalizedString("Match system contacts", comment: "")
            cell.setSettingsImage(image: UIImage(systemName: "iphone")?.applyingSymbolConfiguration(iconConfiguration))
            cell.accessoryView = contactSyncSwitch
            contactSyncSwitch.isOn = NCSettingsController.sharedInstance().isContactSyncEnabled()
            cell.selectionStyle = .none
            return cell

        default:
            return UITableViewCell()
        }
    }

    func userAccountsCell(for indexPath: IndexPath) -> UITableViewCell {
        guard let account = inactiveAccounts[indexPath.row] as? TalkAccount else { return UITableViewCell() }

        let cell: SettingsTableViewCell = tableView.dequeueOrCreateCell(withIdentifier: "AccountCellIdentifier", style: .subtitle)
        cell.textLabel?.text = account.userDisplayName
        cell.detailTextLabel?.text = account.server.replacingOccurrences(of: "https://", with: "")
        cell.detailTextLabel?.lineBreakMode = .byCharWrapping

        if let accountImage = self.getProfilePicture(for: account) {
            cell.setSettingsImage(image: NCUtils.roundedImage(fromImage: accountImage), renderingMode: .alwaysOriginal)
        }

        if account.unreadBadgeNumber > 0 {
            let badgeView = BadgeView(frame: .zero)
            badgeView.badgeColor = NCAppBranding.themeColor()
            badgeView.badgeTextColor = NCAppBranding.themeTextColor()
            badgeView.setBadgeNumber(account.unreadBadgeNumber)
            cell.accessoryView = badgeView
        }

        return cell
    }

    func sectionConfigurationCell(for indexPath: IndexPath) -> UITableViewCell {
        let configurationCellIdentifier = "ConfigurationCellIdentifier"

        let options = getConfigurationSectionOptions()
        let option = options[indexPath.row]

        switch option {
        case ConfigurationSectionOption.kConfigurationSectionOptionVideo.rawValue:
            let cell: SettingsTableViewCell = tableView.dequeueOrCreateCell(withIdentifier: configurationCellIdentifier, style: .default)
            cell.textLabel?.text = NSLocalizedString("Video quality", comment: "")
            cell.setSettingsImage(image: UIImage(systemName: "video")?.applyingSymbolConfiguration(iconConfiguration))

            let resolution = NCSettingsController.sharedInstance().videoSettingsModel.currentVideoResolutionSettingFromStore()
            let resolutionLabel = UILabel()
            resolutionLabel.text = NCSettingsController.sharedInstance().videoSettingsModel.readableResolution(resolution)
            resolutionLabel.textColor = .secondaryLabel
            resolutionLabel.sizeToFit()
            cell.accessoryView = resolutionLabel

            return cell

        case ConfigurationSectionOption.kConfigurationSectionOptionRecents.rawValue:
            let cell: SettingsTableViewCell = tableView.dequeueOrCreateCell(withIdentifier: configurationCellIdentifier, style: .default)
            cell.textLabel?.text = NSLocalizedString("Include calls in call history", comment: "")
            cell.setSettingsImage(image: UIImage(systemName: "clock.arrow.circlepath")?.applyingSymbolConfiguration(iconConfiguration))
            cell.selectionStyle = .none
            cell.accessoryView = includeInRecentsSwitch
            includeInRecentsSwitch.isOn = NCUserDefaults.includeCallsInRecents()
            return cell

        default:
            return UITableViewCell()
        }
    }

    func advancedCell(for indexPath: IndexPath) -> UITableViewCell {
        let advancedCellIdentifier = "AdvancedCellIdentifier"

        let options = getAdvancedSectionOptions()
        let option = options[indexPath.row]

        switch option {
        case AdvancedSectionOption.kAdvancedSectionOptionDiagnostics.rawValue:
            let cell: SettingsTableViewCell = tableView.dequeueOrCreateCell(withIdentifier: advancedCellIdentifier, style: .default)
            cell.textLabel?.text = NSLocalizedString("Diagnostics", comment: "")
            cell.setSettingsImage(image: UIImage(systemName: "gear")?.applyingSymbolConfiguration(iconConfiguration))
            cell.accessoryType = .disclosureIndicator
            return cell

        case AdvancedSectionOption.kAdvancedSectionOptionCallFromOldAccount.rawValue:
            let cell: SettingsTableViewCell = tableView.dequeueOrCreateCell(withIdentifier: advancedCellIdentifier, style: .default)
            cell.textLabel?.text = NSLocalizedString("Calls from old accounts", comment: "")
            cell.setSettingsImage(image: UIImage(systemName: "exclamationmark.triangle.fill")?.applyingSymbolConfiguration(iconConfiguration))
            cell.accessoryType = .disclosureIndicator
            return cell

        case AdvancedSectionOption.kAdvancedSectionOptionCachedImages.rawValue:
            let byteFormatter = ByteCountFormatter()
            byteFormatter.allowedUnits = [.useMB]
            byteFormatter.countStyle = .file

            let cell: SettingsTableViewCell = tableView.dequeueOrCreateCell(withIdentifier: advancedCellIdentifier, style: .default)
            cell.textLabel?.text = NSLocalizedString("Cached images", comment: "")
            cell.setSettingsImage(image: UIImage(systemName: "photo")?.applyingSymbolConfiguration(iconConfiguration))

            let byteCounterLabel = UILabel()
            byteCounterLabel.text = byteFormatter.string(fromByteCount: Int64(self.totalImageCacheSize))
            byteCounterLabel.textColor = .secondaryLabel
            byteCounterLabel.sizeToFit()
            cell.accessoryView = byteCounterLabel

            return cell

        case AdvancedSectionOption.kAdvancedSectionOptionCachedFiles.rawValue:
            let byteFormatter = ByteCountFormatter()
            byteFormatter.allowedUnits = [.useMB]
            byteFormatter.countStyle = .file

            let cell: SettingsTableViewCell = tableView.dequeueOrCreateCell(withIdentifier: advancedCellIdentifier, style: .default)
            cell.textLabel?.text = NSLocalizedString("Cached files", comment: "")
            cell.setSettingsImage(image: UIImage(systemName: "doc")?.applyingSymbolConfiguration(iconConfiguration))

            let byteCounterLabel = UILabel()
            byteCounterLabel.text = byteFormatter.string(fromByteCount: Int64(self.totalFileCacheSize))
            byteCounterLabel.textColor = .secondaryLabel
            byteCounterLabel.sizeToFit()
            cell.accessoryView = byteCounterLabel

            return cell

        default:
            return UITableViewCell()
        }
    }

    func sectionAboutCell(for indexPath: IndexPath) -> UITableViewCell {
        let aboutCellIdentifier = "AboutCellIdentifier"

        let options = getAboutSectionOptions()
        let option = options[indexPath.row]

        switch option {
        case AboutSection.kAboutSectionPrivacy.rawValue:
            let cell: SettingsTableViewCell = tableView.dequeueOrCreateCell(withIdentifier: aboutCellIdentifier, style: .default)
            cell.textLabel?.text = NSLocalizedString("Privacy", comment: "")
            cell.setSettingsImage(image: UIImage(systemName: "lock.shield")?.applyingSymbolConfiguration(iconConfiguration))
            return cell

        case AboutSection.kAboutSectionSourceCode.rawValue:
            let cell: SettingsTableViewCell = tableView.dequeueOrCreateCell(withIdentifier: aboutCellIdentifier, style: .default)
            cell.textLabel?.text = NSLocalizedString("Get source code", comment: "")
            cell.setSettingsImage(image: UIImage(named: "github"))
            return cell

        default:
            return UITableViewCell()
        }
    }

    // UIImage should be optional because userProfileImage (objC) can return a nil value
    func getProfilePicture(for account: TalkAccount) -> UIImage? {
        if let avatar = self.profilePictures[account.accountId] {
            return avatar
        }

        return NCAPIController.sharedInstance().userProfileImage(for: account, with: self.traitCollection.userInterfaceStyle)
    }

    func updateTotalImageCacheSize() {
        let sharedUrlCache = URLCache.shared.currentDiskUsage
        let sdImageCacheSize = SDImageCache.shared.totalDiskSize()
        self.totalImageCacheSize = sharedUrlCache + Int(sdImageCacheSize)
    }

    func updateTotalFileCacheSize() {
        self.totalFileCacheSize = 0

        let fileController = NCChatFileController()
        let talkAccounts = NCDatabaseManager.sharedInstance().allAccounts()

        for account in talkAccounts {
            self.totalFileCacheSize += Int(fileController.getDiskUsage(for: account))
        }
    }
}
