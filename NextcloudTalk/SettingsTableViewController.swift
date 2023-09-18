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
import NextcloudKit
import SafariServices

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
    case kConfigurationSectionOptionBrowser
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
    case kAboutSectionNumber
}

class SettingsTableViewController: UITableViewController, UITextFieldDelegate {
    let kPhoneTextFieldTag = 99
    let kUserSettingsCellIdentifier = "UserSettingsCellIdentifier"
    let kUserSettingsTableCellNibName = "UserSettingsTableViewCell"
    let kAccountCellIdentifier: String = "AccountCellIdentifier"
    let kAccountTableViewCellNibName: String = "AccountTableViewCell"

    let iconConfiguration = UIImage.SymbolConfiguration(pointSize: 18)

    var activeUserStatus: NCUserStatus?
    var readStatusSwitch = UISwitch()
    var typingIndicatorSwitch = UISwitch()
    var contactSyncSwitch = UISwitch()
    var setPhoneAction: UIAlertAction?
    var phoneUtil = NBPhoneNumberUtil()

    var totalImageCacheSize = 0
    var totalFileCacheSize = 0

    var activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
    var inactiveAccounts = NCDatabaseManager.sharedInstance().inactiveAccounts()
    lazy var serverCapabilities: ServerCapabilities = {
        NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId)
    }()

    lazy var profilePictures: [String: UIImage] = {
        var result: [String: UIImage] = [:]

        for account in NCDatabaseManager.sharedInstance().allAccounts() {
            guard let account = account as? TalkAccount else {
                continue
            }

            result[account.accountId] = NCAPIController.sharedInstance().userProfileImage(for: account, with: self.traitCollection.userInterfaceStyle)
        }

        return result
    }()

    @IBOutlet weak var cancelButton: UIBarButtonItem!

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = NSLocalizedString("Settings", comment: "")
        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: NCAppBranding.themeTextColor()]
        self.navigationController?.navigationBar.tintColor = NCAppBranding.themeColor()
        self.tabBarController?.tabBar.tintColor = NCAppBranding.themeColor()
        self.cancelButton.tintColor = NCAppBranding.themeTextColor()
        contactSyncSwitch.frame = .zero
        contactSyncSwitch.addTarget(self, action: #selector(contactSyncValueChanged(_:)), for: .valueChanged)

        readStatusSwitch.frame = .zero
        readStatusSwitch.addTarget(self, action: #selector(readStatusValueChanged(_:)), for: .valueChanged)

        typingIndicatorSwitch.frame = .zero
        typingIndicatorSwitch.addTarget(self, action: #selector(typingIndicatorValueChanged(_:)), for: .valueChanged)

        let themeColor: UIColor = NCAppBranding.themeColor()
        let themeTextColor: UIColor = NCAppBranding.themeTextColor()

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.titleTextAttributes = [.foregroundColor: themeTextColor]
        appearance.backgroundColor = themeColor
        self.navigationItem.standardAppearance = appearance
        self.navigationItem.compactAppearance = appearance
        self.navigationItem.scrollEdgeAppearance = appearance

        tableView.register(UINib(nibName: kUserSettingsTableCellNibName, bundle: nil), forCellReuseIdentifier: kUserSettingsCellIdentifier)
        tableView.register(UINib(nibName: kAccountTableViewCellNibName, bundle: nil), forCellReuseIdentifier: kAccountCellIdentifier)

        NotificationCenter.default.addObserver(self, selector: #selector(appStateHasChanged(notification:)), name: NSNotification.Name.NCAppStateHasChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(contactsHaveBeenUpdated(notification:)), name: NSNotification.Name.NCContactsManagerContactsUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(contactsAccessHasBeenUpdated(notification:)), name: NSNotification.Name.NCContactsManagerContactsAccessUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(userProfileImageUpdated), name: NSNotification.Name.NCUserProfileImageUpdated, object: nil)

        let imageCacheSize = NCImageSessionManager.sharedInstance().cache.currentDiskUsage
        let sdImageCacheSize = SDImageCache.shared.totalDiskSize()
        self.totalImageCacheSize = imageCacheSize + Int(sdImageCacheSize)

        let fileController = NCChatFileController()
        let talkAccounts = NCDatabaseManager.sharedInstance().allAccounts()

        if let talkAccounts = talkAccounts as? [TalkAccount] {
            for account in talkAccounts {
                self.totalFileCacheSize += Int(fileController.getDiskUsage(for: account))
            }
        }

        self.adaptInterfaceForAppState(appState: NCConnectionController.sharedInstance().appState)
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
        if serverCapabilities.userStatus {
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

        // Open links in
        if NCSettingsController.sharedInstance().supportedBrowsers.count > 1 {
            options.append(ConfigurationSectionOption.kConfigurationSectionOptionBrowser.rawValue)
        }

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

    func getSectionForSettingsSection(section: SettingsSection) -> Int {
        let section = getSettingsSections().firstIndex(of: section.rawValue)
        return section ?? 0
    }

    func getIndexPathForConfigurationOption(option: ConfigurationSectionOption) -> IndexPath {
        let section = getSectionForSettingsSection(section: SettingsSection.kSettingsSectionConfiguration)
        let row = getConfigurationSectionOptions().firstIndex(of: option.rawValue)
        return IndexPath(row: row ?? 0, section: section)
    }

    // MARK: User Profile

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

    // MARK: Notifications

    @objc func appStateHasChanged(notification: NSNotification) {
        let appState = notification.userInfo?["appState"]
        if let rawAppState = appState as? UInt32 {
            let appState = AppState(rawValue: rawAppState)
            self.adaptInterfaceForAppState(appState: appState)
        }
    }

    @objc func contactsHaveBeenUpdated(notification: NSNotification) {
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }

    @objc func contactsAccessHasBeenUpdated(notification: NSNotification) {
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }

    @objc func userProfileImageUpdated(notification: NSNotification) {
        self.tableView.reloadSections(IndexSet(integer: SettingsSection.kSettingsSectionUser.rawValue), with: .none)
    }

    // MARK: User Interface

    func adaptInterfaceForAppState(appState: AppState) {
        switch appState {
        case kAppStateReady:
            refreshUserProfile()
        default:
            break
        }
    }

    // MARK: Profile actions

    func userProfilePressed() {
        let userProfileVC = UserProfileTableViewController(withAccount: activeAccount)
        self.navigationController?.pushViewController(userProfileVC, animated: true)
    }

    // MARK: User Status

    func presentUserStatusOptions() {
        if let activeUserStatus = activeUserStatus {
            let viewController = UserStatusTableViewController(userStatus: activeUserStatus)
            self.navigationController?.pushViewController(viewController, animated: true)
        }
    }

    // MARK: User phone number

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
            let countryCode = phoneUtil.getCountryCode(forRegion: location)
            if let countryCode = countryCode {
                textField.text = "+\(countryCode)"
            }
            if let exampleNumber = try? phoneUtil.getExampleNumber(location) {
                textField.placeholder = try? phoneUtil.format(exampleNumber, numberFormat: NBEPhoneNumberFormat.INTERNATIONAL)
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
                    self.view.makeToast(NSLocalizedString("Phone number set successfully", comment: ""), duration: 3, position: CSToastPositionCenter)
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
        let failedPhoneNumber = try? phoneUtil.parse(phoneNumber, defaultRegion: nil)
        if let formattedPhoneNumber = try? phoneUtil.format(failedPhoneNumber, numberFormat: NBEPhoneNumberFormat.INTERNATIONAL) {
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

        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .default, handler: nil)
        failedPhoneNumberDialog.addAction(cancelAction)

        self.present(failedPhoneNumberDialog, animated: true, completion: nil)
    }

    // MARK: UITextField delegate

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if textField.tag == kPhoneTextFieldTag {
            let inputPhoneNumber = (textField.text as NSString?)?.replacingCharacters(in: range, with: string)
            let phoneNumber = try? phoneUtil.parse(inputPhoneNumber, defaultRegion: nil)
            setPhoneAction?.isEnabled = phoneUtil.isValidNumber(phoneNumber)
        }
        return true
    }

    // MARK: Configuration

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

    func presentBrowserSelector() {
        guard let supportedBrowsers = NCSettingsController.sharedInstance().supportedBrowsers else {return}
        let browserConfIndexPath = self.getIndexPathForConfigurationOption(option: ConfigurationSectionOption.kConfigurationSectionOptionBrowser)
        let supportedBrowsersUnwrapped: [String] = supportedBrowsers.compactMap({$0 as? String})
        let defaultBrowser = NCUserDefaults.defaultBrowser()
        let optionsActionSheet = UIAlertController(title: NSLocalizedString("Open links in", comment: ""), message: nil, preferredStyle: .actionSheet)
        supportedBrowsersUnwrapped.forEach { browser in
            let action = UIAlertAction(title: browser, style: .default) { _ in
                NCUserDefaults.setDefaultBrowser(browser)
                self.tableView.reloadData()
            }
            if browser == defaultBrowser {
                action.setValue(UIImage(named: "checkmark")?.withRenderingMode(_: .alwaysOriginal), forKey: "image")
            }
            optionsActionSheet.addAction(action)
        }
        optionsActionSheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
        // Presentation on iPads
        optionsActionSheet.popoverPresentationController?.sourceView = self.tableView
        optionsActionSheet.popoverPresentationController?.sourceRect = self.tableView.rectForRow(at: browserConfIndexPath)
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

    // MARK: Advanced actions

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
            NCImageSessionManager.sharedInstance().cache.removeAllCachedResponses()

            SDImageCache.shared.clearMemory()
            SDImageCache.shared.clearDisk()

            self.tableView.reloadData()
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

            self.tableView.reloadData()
        }
        clearCacheDialog.addAction(clearAction)

        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
        clearCacheDialog.addAction(cancelAction)

        self.present(clearCacheDialog, animated: true, completion: nil)
    }

    func callsFromOldAccountPressed() {
        let vc = CallsFromOldAccountViewController()

        self.navigationController?.pushViewController(vc, animated: true)
    }

    // MARK: Table view data source

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
            return AboutSection.kAboutSectionNumber.rawValue
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
        var cell = UITableViewCell()
        let sections = getSettingsSections()
        let settingsSection = sections[indexPath.section]

        switch settingsSection {
        case SettingsSection.kSettingsSectionUser.rawValue:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: kUserSettingsCellIdentifier, for: indexPath) as? UserSettingsTableViewCell else { return UITableViewCell() }
            cell.userDisplayNameLabel.text = activeAccount.userDisplayName
            let accountServer = activeAccount.server
            cell.serverAddressLabel.text = accountServer.replacingOccurrences(of: "https://", with: "")
            cell.userImageView.image = self.getProfilePicture(for: activeAccount)
            cell.accessoryType = .disclosureIndicator
            return cell
        case SettingsSection.kSettingsSectionUserStatus.rawValue:
            cell = UITableViewCell(style: .subtitle, reuseIdentifier: "UserStatusCellIdentifier")
            if activeUserStatus != nil {
                cell.textLabel?.text = activeUserStatus!.readableUserStatus()
                let statusMessage = activeUserStatus!.readableUserStatusMessage()
                if !statusMessage.isEmpty {
                    cell.textLabel?.text = statusMessage
                }
                if activeUserStatus!.status == kUserStatusDND {
                    cell.detailTextLabel?.text = NSLocalizedString("All notifications are muted", comment: "")
                    cell.detailTextLabel?.numberOfLines = 0
                    cell.detailTextLabel?.textColor = .secondaryLabel
                }
                let statusImage = activeUserStatus!.userStatusImageName(ofSize: 24)
                cell.imageView?.image = UIImage(named: statusImage)
            } else {
                cell.textLabel?.text = NSLocalizedString("Fetching status …", comment: "")
            }
            cell.accessoryType = .disclosureIndicator
            return cell
        case SettingsSection.kSettingsSectionAccountSettings.rawValue:
            cell = userSettingsCell(for: indexPath)
        case SettingsSection.kSettingsSectionOtherAccounts.rawValue:
            cell = userAccountsCell(for: indexPath)
        case SettingsSection.kSettingsSectionConfiguration.rawValue:
            cell = sectionConfigurationCell(for: indexPath)
        case SettingsSection.kSettingsSectionAdvanced.rawValue:
            cell = advancedCell(for: indexPath)
        case SettingsSection.kSettingsSectionAbout.rawValue:
            cell = sectionAboutCell(for: indexPath)
        default:
            break
        }
        return cell
    }

    func didSelectOtherAccountSectionCell(for indexPath: IndexPath) {
        if let account = inactiveAccounts[indexPath.row] as? TalkAccount {
            NCSettingsController.sharedInstance().setActiveAccountWithAccountId(account.accountId)
        }
    }

    func didSelectSettingsSectionCell(for indexPath: IndexPath) {
        let options = getConfigurationSectionOptions()
        let option = options[indexPath.row]
        switch option {
        case ConfigurationSectionOption.kConfigurationSectionOptionVideo.rawValue:
            self.presentVideoResoultionsSelector()
        case ConfigurationSectionOption.kConfigurationSectionOptionBrowser.rawValue:
            self.presentBrowserSelector()
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
        switch indexPath.row {
        case AboutSection.kAboutSectionPrivacy.rawValue:
            let safariVC = SFSafariViewController(url: URL(string: "https://nextcloud.com/privacy")!)
            self.present(safariVC, animated: true, completion: nil)
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
    // Cell configuration for every section
    func userSettingsCell(for indexPath: IndexPath) -> UITableViewCell {
        let readStatusCellIdentifier = "ReadStatusCellIdentifier"
        let typingIndicatorCellIdentifier = "TypingIndicatorCellIdentifier"
        let contactsSyncCellIdentifier = "ContactsSyncCellIdentifier"

        let options = getAccountSettingsSectionOptions()
        let option = options[indexPath.row]
        var cell = UITableViewCell()

        switch option {
        case AccountSettingsOptions.kAccountSettingsReadStatusPrivacy.rawValue:
            cell = tableView.dequeueReusableCell(withIdentifier: readStatusCellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: readStatusCellIdentifier)
            cell.textLabel?.text = NSLocalizedString("Read status", comment: "")
            cell.selectionStyle = .none
            cell.imageView?.image = UIImage(named: "check-all")?.withRenderingMode(.alwaysTemplate)
            cell.imageView?.tintColor = .secondaryLabel
            cell.imageView?.contentMode = .scaleAspectFit
            cell.accessoryView = readStatusSwitch
            readStatusSwitch.isOn = !serverCapabilities.readStatusPrivacy

        case AccountSettingsOptions.kAccountSettingsTypingPrivacy.rawValue:
            cell = tableView.dequeueReusableCell(withIdentifier: typingIndicatorCellIdentifier) ?? UITableViewCell(style: .subtitle, reuseIdentifier: typingIndicatorCellIdentifier)
            cell.textLabel?.text = NSLocalizedString("Typing indicator", comment: "")
            cell.selectionStyle = .none
            cell.imageView?.image = UIImage(systemName: "rectangle.and.pencil.and.ellipsis")
            cell.imageView?.tintColor = .secondaryLabel
            cell.imageView?.contentMode = .scaleAspectFit
            cell.accessoryView = typingIndicatorSwitch
            typingIndicatorSwitch.isOn = !serverCapabilities.typingPrivacy

            let externalSignalingController = NCSettingsController.sharedInstance().externalSignalingController(forAccountId: activeAccount.accountId)
            let externalSignalingServerUsed = externalSignalingController?.isEnabled() ?? false

            if !externalSignalingServerUsed {
                cell.detailTextLabel?.text = NSLocalizedString("Typing indicators are only available when using a high performance backend (HPB)", comment: "")
            } else {
                cell.detailTextLabel?.text = nil
            }

        case AccountSettingsOptions.kAccountSettingsContactsSync.rawValue:
            cell = tableView.dequeueReusableCell(withIdentifier: contactsSyncCellIdentifier) ?? UITableViewCell(style: .subtitle, reuseIdentifier: contactsSyncCellIdentifier)
            cell.textLabel?.text = NSLocalizedString("Phone number integration", comment: "")
            cell.detailTextLabel?.text = NSLocalizedString("Match system contacts", comment: "")
            cell.selectionStyle = .none
            cell.imageView?.image = UIImage(systemName: "iphone")?.applyingSymbolConfiguration(iconConfiguration)
            cell.imageView?.tintColor = .secondaryLabel
            cell.accessoryView = contactSyncSwitch
            contactSyncSwitch.isOn = NCSettingsController.sharedInstance().isContactSyncEnabled()
        default:
            break
        }
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.numberOfLines = 0
        cell.detailTextLabel?.textColor = .secondaryLabel
        return cell
    }

    func userAccountsCell(for indexPath: IndexPath) -> UITableViewCell {
        let account = inactiveAccounts[indexPath.row] as? TalkAccount
        guard let cell = tableView.dequeueReusableCell(withIdentifier: kAccountCellIdentifier, for: indexPath) as? AccountTableViewCell else { return UITableViewCell() }
        if let account = account {
            cell.accountNameLabel.text = account.userDisplayName
            let accountServer = account.server.replacingOccurrences(of: "https://", with: "")
            cell.accountServerLabel.text = accountServer
            cell.accountImageView.image = self.getProfilePicture(for: account)
            cell.accessoryView = nil
            if account.unreadBadgeNumber > 0 {
                let badgeView = RoundedNumberView()
                badgeView.highlightType = kHighlightTypeImportant
                badgeView.number = account.unreadBadgeNumber
                cell.accessoryView = badgeView
            }
        }
        return cell
    }

    func sectionConfigurationCell(for indexPath: IndexPath) -> UITableViewCell {
        let videoConfigurationCellIdentifier = "VideoConfigurationCellIdentifier"
        let browserConfigurationCellIdentifier = "BrowserConfigurationCellIdentifier"
        let options = getConfigurationSectionOptions()
        let option = options[indexPath.row]
        var cell = UITableViewCell()
        switch option {
        case ConfigurationSectionOption.kConfigurationSectionOptionVideo.rawValue:
            cell = UITableViewCell(style: .default, reuseIdentifier: videoConfigurationCellIdentifier)
            cell.textLabel?.text = NSLocalizedString("Video quality", comment: "")
            cell.imageView?.image = UIImage(systemName: "video")?.applyingSymbolConfiguration(iconConfiguration)
            cell.imageView?.tintColor = .secondaryLabel
            let resolution = NCSettingsController.sharedInstance().videoSettingsModel.currentVideoResolutionSettingFromStore()
            let resolutionLabel = UILabel()
            resolutionLabel.text = NCSettingsController.sharedInstance().videoSettingsModel.readableResolution(resolution)
            resolutionLabel.textColor = .secondaryLabel
            resolutionLabel.sizeToFit()
            cell.accessoryView = resolutionLabel
        case ConfigurationSectionOption.kConfigurationSectionOptionBrowser.rawValue:
            cell = UITableViewCell(style: .default, reuseIdentifier: browserConfigurationCellIdentifier)
            cell.textLabel?.text = NSLocalizedString("Open links in", comment: "")
            cell.imageView?.image = UIImage(systemName: "network")?.applyingSymbolConfiguration(iconConfiguration)
            cell.imageView?.tintColor = .secondaryLabel
            let browserLabel = UILabel()
            browserLabel.text = NCUserDefaults.defaultBrowser()
            browserLabel.textColor = .secondaryLabel
            browserLabel.sizeToFit()
            cell.accessoryView = browserLabel
        default:
            break
        }
        cell.textLabel?.numberOfLines = 0
        return cell
    }

    func advancedCell(for indexPath: IndexPath) -> UITableViewCell {
        let advancedCellDisclosureIdentifier = "AdvancedCellDisclosureIdentifier"
        let advancedCellValue1Identifier = "AdvancedCellType1Identifier"

        if indexPath.row == AdvancedSectionOption.kAdvancedSectionOptionDiagnostics.rawValue {
            let cell = UITableViewCell(style: .default, reuseIdentifier: advancedCellDisclosureIdentifier)
            cell.textLabel?.text = NSLocalizedString("Diagnostics", comment: "")
            cell.textLabel?.numberOfLines = 0
            cell.imageView?.image = UIImage(systemName: "gear")?.applyingSymbolConfiguration(iconConfiguration)
            cell.imageView?.tintColor = .secondaryLabel
            cell.accessoryType = .disclosureIndicator

            return cell

        } else if indexPath.row == AdvancedSectionOption.kAdvancedSectionOptionCallFromOldAccount.rawValue {
            let cell = UITableViewCell(style: .default, reuseIdentifier: advancedCellDisclosureIdentifier)
            cell.textLabel?.text = NSLocalizedString("Calls from old accounts", comment: "")
            cell.textLabel?.numberOfLines = 0
            cell.imageView?.image = UIImage(systemName: "exclamationmark.triangle.fill")?.applyingSymbolConfiguration(iconConfiguration)
            cell.imageView?.tintColor = UIColor.systemOrange
            cell.accessoryType = .disclosureIndicator

            return cell

        } else if indexPath.row == AdvancedSectionOption.kAdvancedSectionOptionCachedImages.rawValue {
            let byteFormatter = ByteCountFormatter()
            byteFormatter.allowedUnits = [.useMB]
            byteFormatter.countStyle = .file

            let cell = UITableViewCell(style: .default, reuseIdentifier: advancedCellValue1Identifier)
            cell.textLabel?.text = NSLocalizedString("Cached images", comment: "")
            cell.textLabel?.numberOfLines = 0
            cell.imageView?.image = UIImage(systemName: "photo")?.applyingSymbolConfiguration(iconConfiguration)
            cell.imageView?.tintColor = .secondaryLabel
            let byteCounterLabel = UILabel()
            byteCounterLabel.text = byteFormatter.string(fromByteCount: Int64(self.totalImageCacheSize))
            byteCounterLabel.textColor = .secondaryLabel
            byteCounterLabel.sizeToFit()
            cell.accessoryView = byteCounterLabel

            return cell

        } else {
            // AdvancedSectionOption.kAdvancedSectionOptionCachedFiles.rawValue

            let byteFormatter = ByteCountFormatter()
            byteFormatter.allowedUnits = [.useMB]
            byteFormatter.countStyle = .file

            let cell = UITableViewCell(style: .default, reuseIdentifier: advancedCellValue1Identifier)
            cell.textLabel?.text = NSLocalizedString("Cached files", comment: "")
            cell.textLabel?.numberOfLines = 0
            cell.imageView?.image = UIImage(systemName: "doc")?.applyingSymbolConfiguration(iconConfiguration)
            cell.imageView?.tintColor = .secondaryLabel
            let byteCounterLabel = UILabel()
            byteCounterLabel.text = byteFormatter.string(fromByteCount: Int64(self.totalFileCacheSize))
            byteCounterLabel.textColor = .secondaryLabel
            byteCounterLabel.sizeToFit()
            cell.accessoryView = byteCounterLabel

            return cell
        }
    }

    func sectionAboutCell(for indexPath: IndexPath) -> UITableViewCell {
        let privacyCellIdentifier = "PrivacyCellIdentifier"
        let sourceCodeCellIdentifier = "SourceCodeCellIdentifier"
        var cell = UITableViewCell()
        switch indexPath.row {
        case AboutSection.kAboutSectionPrivacy.rawValue:
            cell =
            UITableViewCell(style: .default, reuseIdentifier: privacyCellIdentifier)
            cell.textLabel?.text = NSLocalizedString("Privacy", comment: "")
            cell.imageView?.image = UIImage(systemName: "lock.shield")?.applyingSymbolConfiguration(iconConfiguration)
            cell.imageView?.tintColor = .secondaryLabel
        case AboutSection.kAboutSectionSourceCode.rawValue:
            cell =
            UITableViewCell(style: .default, reuseIdentifier: sourceCodeCellIdentifier)
            cell.textLabel?.text = NSLocalizedString("Get source code", comment: "")
            cell.imageView?.image = UIImage(named: "github")?.withRenderingMode(.alwaysTemplate)
            cell.imageView?.tintColor = .secondaryLabel
            cell.imageView?.contentMode = .scaleAspectFit
        default:
            break
        }
        cell.textLabel?.numberOfLines = 0
        return cell
    }

    func getProfilePicture(for account: TalkAccount) -> UIImage {
        if let avatar = self.profilePictures[account.accountId] {
            return avatar
        }

        return NCAPIController.sharedInstance().userProfileImage(for: account, with: self.traitCollection.userInterfaceStyle)
    }
}
