//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import NextcloudKit

// MARK: - Notification names

extension NSNotification.Name {
    static let NCSettingsControllerDidChangeActiveAccount = Notification.Name(rawValue: "NCSettingsControllerDidChangeActiveAccountNotification")
}

@objc extension NSNotification {
    public static let NCSettingsControllerDidChangeActiveAccount = Notification.Name.NCSettingsControllerDidChangeActiveAccount
}

// MARK: - User profile keys

enum UserProfileField {
    static let userId = "id"
    static let displayName = "displayname"
    static let displayNameScope = "displaynameScope"
    static let email = "email"
    static let emailScope = "emailScope"
    static let phone = "phone"
    static let phoneScope = "phoneScope"
    static let address = "address"
    static let addressScope = "addressScope"
    static let website = "website"
    static let websiteScope = "websiteScope"
    static let twitter = "twitter"
    static let twitterScope = "twitterScope"
    static let avatarScope = "avatarScope"
}

enum UserProfileScope {
    static let `private` = "v2-private"
    static let local = "v2-local"
    static let federated = "v2-federated"
    static let published = "v2-published"
}

private let kPreferredFileSorting = "preferredFileSorting"
private let kContactSyncEnabled = "contactSyncEnabled"
private let kDidReceiveCallsFromOldAccount = "receivedCallsFromOldAccount"

@objcMembers
public class NCSettingsController: NSObject {

    static let shared = NCSettingsController()

    @available(*, renamed: "shared")
    static func sharedInstance() -> NCSettingsController {
        return NCSettingsController.shared
    }

    private typealias AccountId = String

    public var videoSettingsModel = ARDSettingsModel()
    private var signalingConfigurations: [AccountId: SignalingSettings] = [:]
    private var externalSignalingControllers: [AccountId: NCExternalSignalingController] = [:]

    private var updateAlertController: UIAlertController?
    private var updateAlertControllerAccountId: String?

    override init() {
        super.init()

        self.configureDatabase()
        self.checkStoredDataInKeychain()
        self.resetPerAppLaunchSettings()

        NotificationCenter.default.addObserver(self, selector: #selector(tokenRevokedResponseReceived(_:)), name: .NCTokenRevokedResponseReceived, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(upgradeRequiredResponseReceived(_:)), name: .NCUpgradeRequiredResponseReceived, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(talkConfigurationHasChanged(_:)), name: .NCTalkConfigurationHashChanged, object: nil)
    }

    // MARK: - Database

    private func configureDatabase() {
        // Init database
        _ = NCDatabaseManager.sharedInstance()
    }

    private func checkStoredDataInKeychain() {
        // Remove data stored in the Keychain if there are no accounts configured
        // This step should always be done before the possible account migration
        if NCDatabaseManager.sharedInstance().numberOfAccounts() == 0 {
            NSLog("Removing all data stored in Keychain")
            NCKeyChainController.sharedInstance().removeAllItems()
        }
    }

    private func resetPerAppLaunchSettings() {
        // Reset "threadsLastCheckTimestamp" on every app fresh launch
        let realm = RLMRealm.default()
        try? realm.transaction {
            for case let account as TalkAccount in TalkAccount.allObjects() {
                account.threadsLastCheckTimestamp = 0
            }
        }
    }

    // MARK: - User accounts

    public func addNewAccount(forUser user: String, withToken token: String, inServer server: String) {
        let accountId = NCDatabaseManager.sharedInstance().accountId(forUser: user, inServer: server)
        let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId)

        if account == nil {
            NCDatabaseManager.sharedInstance().createAccount(forUser: user, inServer: server)
            NCDatabaseManager.sharedInstance().setActiveAccountWithAccountId(accountId)
            NCKeyChainController.sharedInstance().setToken(token, forAccountId: accountId)
            self.subscribeForPushNotifications(forAccountId: accountId, withCompletionBlock: nil)
            self.createAccountsFile()
        } else {
            self.setActiveAccountWithAccountId(accountId)
            NotificationPresenter.shared().present(text: NSLocalizedString("Account already added", comment: ""), dismissAfterDelay: 4.0, includedStyle: .success)
        }
    }

    public func setActiveAccountWithAccountId(_ accountId: String) {
        NCUserInterfaceController.sharedInstance().presentConversationsList()
        NCDatabaseManager.sharedInstance().setActiveAccountWithAccountId(accountId)
        NCDatabaseManager.sharedInstance().resetUnreadBadgeNumber(forAccountId: accountId)
        NCNotificationController.sharedInstance().removeAllNotifications(forAccountId: accountId)
        NCConnectionController.shared.checkAppState()

        let userInfo = ["accountId": accountId]
        NotificationCenter.default.post(name: .NCSettingsControllerDidChangeActiveAccount, object: self, userInfo: userInfo)
    }

    public func createAccountsFile() {
        guard useAppsGroup.boolValue else {
            return
        }

        // Create accounts data
        guard let appsGroupFolderURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appsGroupIdentifier) else {
            return
        }

        var accounts: [NKShareAccounts.DataAccounts] = []
        for account in NCDatabaseManager.sharedInstance().allAccounts() {
            var accountImage = NCAPIController.sharedInstance().userProfileImage(forAccount: account, withStyle: .light)
            if let image = accountImage {
                accountImage = NCUtils.roundedImage(fromImage: image)
            }
            let accountData = NKShareAccounts.DataAccounts(withUrl: account.server, user: account.user, name: account.userDisplayName, image: accountImage)
            accounts.append(accountData)
        }

        let error = NKShareAccounts().putShareAccounts(at: appsGroupFolderURL, app: "nextcloudtalk", dataAccounts: accounts)
        NSLog("Created accounts file. Error: %@", error?.localizedDescription ?? "nil")
    }

    // MARK: - Notifications

    func tokenRevokedResponseReceived(_ notification: Notification) {
        guard let accountId = notification.userInfo?["accountId"] as? String else { return }
        let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId)

        // Always remove the account, whether the token has been revoked or marked for remote wipe
        self.logoutAccount(withAccountId: accountId) { error in
            guard error == nil, let account else { return }

            NCUserInterfaceController.sharedInstance().presentConversationsList()
            NCUserInterfaceController.sharedInstance().presentLoggedOutInvalidCredentialsAlert()
            NCConnectionController.shared.checkAppState()

            // If the token was marked for remote wipe, confirm the wipe
            NCAPIController.sharedInstance().checkWipeStatus(forAccount: account) { wipe, _ in
                if wipe {
                    NCAPIController.sharedInstance().confirmWipe(forAccount: account, completionBlock: nil)
                }
            }
        }
    }

    func upgradeRequiredResponseReceived(_ notification: Notification) {
        guard let accountId = notification.userInfo?["accountId"] as? String else { return }

        if self.updateAlertController == nil || self.updateAlertControllerAccountId != accountId {
            self.createUpdateAlertController(forAccountId: accountId)
        }

        if let updateAlertController = self.updateAlertController {
            NCUserInterfaceController.sharedInstance().presentAlertIfNotPresentedAlready(updateAlertController)
        }
    }

    private func createUpdateAlertController(forAccountId accountId: String) {
        let appStoreUrlString = "itms-apps://itunes.apple.com/app/id"

        guard let appStoreUrl = URL(string: appStoreUrlString) else {
            return
        }

        let canOpenAppStore = UIApplication.shared.canOpenURL(appStoreUrl)

        let messageNotification = NSLocalizedString("The app is too old and no longer supported by this server.", comment: "")
        let messageAction = canOpenAppStore ? NSLocalizedString("Please update.", comment: "") : NSLocalizedString("Please contact your system administrator.", comment: "")
        let message = "\(messageNotification) \(messageAction)"

        let alertController = UIAlertController(title: NSLocalizedString("App is outdated", comment: ""), message: message, preferredStyle: .alert)

        self.updateAlertController = alertController
        self.updateAlertControllerAccountId = accountId

        if canOpenAppStore {
            let updateButton = UIAlertAction(title: NSLocalizedString("Update", comment: ""), style: .default) { _ in
                NCAPIController.sharedInstance().getAppStoreAppId { appId, _ in
                    if let appId, !appId.isEmpty, let appStoreURL = URL(string: "\(appStoreUrlString)\(appId)") {
                        UIApplication.shared.open(appStoreURL, options: [:], completionHandler: nil)
                    }

                    self.updateAlertControllerAccountId = nil
                }
            }

            alertController.addAction(updateButton)
        }

        if !NCDatabaseManager.sharedInstance().inactiveAccounts().isEmpty {
            let switchAccountButton = UIAlertAction(title: NSLocalizedString("Switch account", comment: ""), style: .default) { _ in
                self.switchToAnyInactiveAccount()
                self.updateAlertControllerAccountId = nil
            }

            alertController.addAction(switchAccountButton)
        }

        let logoutButton = UIAlertAction(title: NSLocalizedString("Log out", comment: ""), style: .destructive) { _ in
            NCUserInterfaceController.sharedInstance().logOutAccount(withAccountId: accountId)
            self.updateAlertControllerAccountId = nil
        }

        alertController.addAction(logoutButton)
    }

    func talkConfigurationHasChanged(_ notification: Notification) {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        guard let accountId = notification.userInfo?["accountId"] as? String,
              let configurationHash = notification.userInfo?["configurationHash"] as? String,
              activeAccount.accountId == accountId
        else { return }

        self.getCapabilitiesForAccountId(accountId) { error in
            if error != nil {
                return
            }

            let bgTask = BGTaskHelper.startBackgroundTask(withName: "NCUpdateSignalingConfiguration")

            self.updateSignalingConfiguration(forAccountId: accountId) { _, error in
                if error == nil {
                    NCDatabaseManager.sharedInstance().updateTalkConfigurationHash(forAccountId: accountId, withHash: configurationHash)
                }

                bgTask.stopBackgroundTask()
            }
        }
    }

    // MARK: - User defaults

    public func getPreferredFileSorting() -> NCPreferredFileSorting {
        let rawValue = (UserDefaults.standard.object(forKey: kPreferredFileSorting) as? NSNumber)?.intValue ?? 0

        guard let sorting = NCPreferredFileSorting(rawValue: rawValue), rawValue != 0 else {
            UserDefaults.standard.set(NSNumber(value: NCPreferredFileSorting.modificationDateSorting.rawValue), forKey: kPreferredFileSorting)
            return .modificationDateSorting
        }

        return sorting
    }

    public func setPreferredFileSorting(_ sorting: NCPreferredFileSorting) {
        UserDefaults.standard.set(NSNumber(value: sorting.rawValue), forKey: kPreferredFileSorting)
    }

    public func isContactSyncEnabled() -> Bool {
        // Migration from global setting to per-account setting
        if (UserDefaults.standard.object(forKey: kContactSyncEnabled) as? NSNumber)?.boolValue == true {
            // If global setting was enabled then we enable contact sync for all accounts
            let realm = RLMRealm.default()
            try? realm.transaction {
                for case let account as TalkAccount in TalkAccount.allObjects() {
                    account.hasContactSyncEnabled = true
                }
            }
            // Remove global setting
            UserDefaults.standard.removeObject(forKey: kContactSyncEnabled)
            UserDefaults.standard.synchronize()
            return true
        }

        return NCDatabaseManager.sharedInstance().activeAccount().hasContactSyncEnabled
    }

    public func setContactSync(_ enabled: Bool) {
        let realm = RLMRealm.default()
        try? realm.transaction {
            let account = TalkAccount.objects(where: "active = true").firstObject() as? TalkAccount
            account?.hasContactSyncEnabled = enabled
        }
    }

    public func didReceiveCallsFromOldAccount() -> Bool {
        return (UserDefaults.standard.object(forKey: kDidReceiveCallsFromOldAccount) as? NSNumber)?.boolValue ?? false
    }

    public func setDidReceiveCallsFromOldAccount(_ receivedOldCalls: Bool) {
        UserDefaults.standard.set(NSNumber(value: receivedOldCalls), forKey: kDidReceiveCallsFromOldAccount)
    }

    // MARK: - User Profile

    public func getUserProfile(forAccountId accountId: String, withCompletionBlock block: @escaping (_ error: OcsError?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId) else {
            block(OcsError.genericError())
            return
        }

        NCAPIController.sharedInstance().getUserProfile(forAccount: account) { userProfile, error in
            guard error == nil, let userProfile else {
                NSLog("Error while getting the user profile")
                block(error)
                return
            }

            let email = (userProfile[UserProfileField.email] as? String) ?? ""

            let bgTask = BGTaskHelper.startBackgroundTask(withName: "NCSetUserProfile")
            let realm = RLMRealm.default()
            try? realm.transaction {
                guard let managedActiveAccount = TalkAccount.objects(where: "accountId = %@", account.accountId).firstObject() as? TalkAccount else {
                    block(OcsError.genericError())
                    return
                }

                managedActiveAccount.userId = (userProfile[UserProfileField.userId] as? String) ?? ""
                // "display-name" is returned by /cloud/user endpoint
                // change to UserProfileField.displayName ("displayName") when using /cloud/users/{userId} endpoint
                managedActiveAccount.userDisplayName = (userProfile["display-name"] as? String) ?? ""
                managedActiveAccount.userDisplayNameScope = (userProfile[UserProfileField.displayNameScope] as? String) ?? ""
                managedActiveAccount.phone = (userProfile[UserProfileField.phone] as? String) ?? ""
                managedActiveAccount.phoneScope = (userProfile[UserProfileField.phoneScope] as? String) ?? ""
                managedActiveAccount.email = email
                managedActiveAccount.emailScope = (userProfile[UserProfileField.emailScope] as? String) ?? ""
                managedActiveAccount.address = (userProfile[UserProfileField.address] as? String) ?? ""
                managedActiveAccount.addressScope = (userProfile[UserProfileField.addressScope] as? String) ?? ""
                managedActiveAccount.website = (userProfile[UserProfileField.website] as? String) ?? ""
                managedActiveAccount.websiteScope = (userProfile[UserProfileField.websiteScope] as? String) ?? ""
                managedActiveAccount.twitter = (userProfile[UserProfileField.twitter] as? String) ?? ""
                managedActiveAccount.twitterScope = (userProfile[UserProfileField.twitterScope] as? String) ?? ""
                managedActiveAccount.avatarScope = (userProfile[UserProfileField.avatarScope] as? String) ?? ""

                let unmanagedUpdatedAccount = TalkAccount(value: managedActiveAccount)
                NCAPIController.sharedInstance().saveProfileImage(forAccount: unmanagedUpdatedAccount)

                block(nil)
            }
            bgTask.stopBackgroundTask()
        }
    }

    public func getUserGroupsAndTeams(forAccountId accountId: String) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId) else {
            return
        }

        NCAPIController.sharedInstance().getUserGroups(forAccount: account) { groupIds, error in
            guard error == nil else {
                NSLog("Error while getting user's groups")
                return
            }

            let bgTask = BGTaskHelper.startBackgroundTask(withName: "NCSetUserGroups")
            let realm = RLMRealm.default()
            try? realm.transaction {
                guard let managedActiveAccount = TalkAccount.objects(where: "accountId = %@", account.accountId).firstObject() as? TalkAccount else {
                    return
                }

                managedActiveAccount.groupIds.removeAllObjects()
                managedActiveAccount.groupIds.addObjects((groupIds ?? []) as NSArray)
            }
            bgTask.stopBackgroundTask()
        }

        NCAPIController.sharedInstance().getUserTeams(forAccount: account) { teamIds, error in
            guard error == nil else {
                NSLog("Error while getting user's teams")
                return
            }

            let bgTask = BGTaskHelper.startBackgroundTask(withName: "NCSetUserTeams")
            let realm = RLMRealm.default()
            try? realm.transaction {
                guard let managedActiveAccount = TalkAccount.objects(where: "accountId = %@", account.accountId).firstObject() as? TalkAccount else {
                    return
                }

                managedActiveAccount.teamIds.removeAllObjects()
                managedActiveAccount.teamIds.addObjects((teamIds ?? []) as NSArray)
            }
            bgTask.stopBackgroundTask()
        }
    }

    public func logoutAccount(withAccountId accountId: String, withCompletionBlock block: ((_ error: NSError?) -> Void)?) {
        guard let removingAccount = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId) else {
            block?(NSError(domain: NSCocoaErrorDomain, code: 0, userInfo: nil))
            return
        }

        if removingAccount.deviceIdentifier != nil {
            NCAPIController.sharedInstance().unsubscribeAccount(removingAccount, fromNextcloudServerWithCompletionBlock: { error in
                if error == nil {
                    NSLog("Unsubscribed from NC server!!!")
                } else {
                    NSLog("Error while unsubscribing from NC server.")
                }
            })
            NCAPIController.sharedInstance().unsubscribeAccount(removingAccount, fromPushServerWithCompletionBlock: { error in
                if error == nil {
                    NSLog("Unsubscribed from Push Notification server!!!")
                } else {
                    NSLog("Error while unsubscribing from Push Notification server.")
                }
            })
        }

        let extSignalingController = self.externalSignalingController(forAccountId: removingAccount.accountId)
        extSignalingController?.disconnect()
        NCAPIController.sharedInstance().removeProfileImage(forAccount: removingAccount)
        NCAPIController.sharedInstance().removeAPISessionManager(forAccount: removingAccount)
        NCDatabaseManager.sharedInstance().removeAccount(withAccountId: removingAccount.accountId)
        NCChatFileController().deleteDownloadDirectory(for: removingAccount)
        NCRoomsManager.shared.chatViewController?.leaveChat()
        self.createAccountsFile()

        // Activate any of the inactive accounts
        self.switchToAnyInactiveAccount()

        block?(nil)
    }

    private func switchToAnyInactiveAccount() {
        if let inactiveAccount = NCDatabaseManager.sharedInstance().inactiveAccounts().first {
            self.setActiveAccountWithAccountId(inactiveAccount.accountId)
        }
    }

    // MARK: - Signaling Configuration

    public func updateSignalingConfiguration(forAccountId accountId: String, withCompletionBlock block: @escaping (_ signalingServer: NCExternalSignalingController?, _ error: NSError?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId) else {
            block(nil, NSError(domain: NSCocoaErrorDomain, code: 0, userInfo: nil))
            return
        }

        NCAPIController.sharedInstance().getSignalingSettings(for: account, forRoom: nil) { settings, error in
            guard error == nil else {
                NSLog("Error while getting signaling configuration")
                block(nil, error as NSError?)
                return
            }

            guard let settings, !account.accountId.isEmpty else {
                block(nil, NSError(domain: NSCocoaErrorDomain, code: 0, userInfo: nil))
                return
            }

            let extSignalingController = self.setSignalingConfiguration(forAccountId: account.accountId, withSettings: settings)
            block(extSignalingController, nil)
        }
    }

    @discardableResult
    public func setSignalingConfiguration(forAccountId accountId: String, withSettings signalingSettings: SignalingSettings) -> NCExternalSignalingController? {
        self.signalingConfigurations[accountId] = signalingSettings

        guard let server = signalingSettings.server, !server.isEmpty,
              let ticket = signalingSettings.ticket, !ticket.isEmpty
        else { return nil }

        let bgTask = BGTaskHelper.startBackgroundTask(withName: "NCSetSignalingConfiguration")

        if let extSignalingController = self.externalSignalingControllers[accountId] {
            extSignalingController.disconnect()
            self.externalSignalingControllers.removeValue(forKey: accountId)
        }

        var extSignalingController: NCExternalSignalingController?

        if let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId) {
            extSignalingController = NCExternalSignalingController(account: account, serverUrl: server, ticket: ticket)
            self.externalSignalingControllers[accountId] = extSignalingController
        }

        bgTask.stopBackgroundTask()

        return extSignalingController
    }

    public func ensureSignalingConfiguration(forAccountId accountId: String, with settings: SignalingSettings?, withCompletionBlock block: @escaping (_ signalingServer: NCExternalSignalingController?) -> Void) {
        if let signalingController = self.externalSignalingControllers[accountId] {
            block(signalingController)
            return
        }

        NCLog.log("Ensure signaling configuration -> Setting configuration")

        if let settings {
            // In case settings are provided, we use these provided settings
            let extSignalingController = self.setSignalingConfiguration(forAccountId: accountId, withSettings: settings)
            block(extSignalingController)
        } else {
            // There were no settings provided for that call, we have to update the settings
            self.updateSignalingConfiguration(forAccountId: accountId) { signalingServer, _ in
                block(signalingServer)
            }
        }
    }

    public func signalingConfiguration(forAccountId accountId: String) -> SignalingSettings? {
        return self.signalingConfigurations[accountId]
    }

    public func externalSignalingController(forAccountId accountId: String) -> NCExternalSignalingController? {
        return self.externalSignalingControllers[accountId]
    }

    public func connectDisconnectedExternalSignalingControllers() {
        for extSignalingController in self.externalSignalingControllers.values where extSignalingController.disconnected {
            extSignalingController.connect()
        }
    }

    public func disconnectAllExternalSignalingControllers() {
        for extSignalingController in self.externalSignalingControllers.values {
            extSignalingController.disconnect()
        }
    }

    // MARK: - Server Capabilities

    public func getCapabilitiesForAccountId(_ accountId: String, withCompletionBlock block: ((_ error: OcsError?) -> Void)?) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId) else {
            block?(OcsError.genericError())
            return
        }

        NCAPIController.sharedInstance().getServerCapabilities(forAccount: account) { serverCapabilities, error in
            guard error == nil, let serverCapabilities else {
                NSLog("Error while getting server capabilities")
                block?(error)
                return
            }

            let bgTask = BGTaskHelper.startBackgroundTask(withName: "NCUpdateCapabilitiesTransaction")
            NCDatabaseManager.sharedInstance().setServerCapabilities(serverCapabilities, forAccountId: account.accountId)
            self.checkServerCapabilities(forAccount: account)
            bgTask.stopBackgroundTask()

            NotificationCenter.default.post(name: .NCServerCapabilitiesUpdated, object: self, userInfo: nil)

            block?(nil)
        }
    }

    private func checkServerCapabilities(forAccount account: TalkAccount) {
        guard let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId) else {
            return
        }

        let talkFeatures = serverCapabilities.talkCapabilities.value(forKey: "self") as? [String]
        if talkFeatures == nil || talkFeatures?.isEmpty == true {
            NotificationCenter.default.post(name: .NCTalkNotInstalled, object: self, userInfo: nil)
        } else if talkFeatures?.contains(kMinimumRequiredTalkCapability) == false {
            NotificationCenter.default.post(name: .NCOutdatedTalkVersion, object: self, userInfo: nil)
        }
    }

    public func canCreateGroupAndPublicRooms() -> Bool {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        if let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId) {
            return serverCapabilities.canCreate
        }
        return true
    }

    public func isGuestsAppEnabled() -> Bool {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        if let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId) {
            return serverCapabilities.guestsAppEnabled
        }
        return false
    }

    public func isReferenceApiSupported() -> Bool {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        if let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId) {
            return serverCapabilities.referenceApiSupported
        }
        return false
    }

    public func isRecordingEnabled() -> Bool {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        if let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId),
           NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityRecordingV1) {
            return serverCapabilities.recordingEnabled
        }
        return false
    }

    func isEndToEndEncryptedCallingEnabled(forAccount accountId: String) -> Bool {
        return NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: accountId)?.e2eeCallsEnabled ?? false
    }

    func isRoomsSortingSupported(forAccountId accountId: String) -> Bool {
        guard let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: accountId)
        else { return false }

        return NCRoomSortOrder(rawValue: serverCapabilities.roomsSortOrder) != .unsupported &&
        NCRoomGroupMode(rawValue: serverCapabilities.roomsGroupMode) != .unsupported
    }

    public func passwordPolicyGenerateAPIEndpoint() -> String? {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        return NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId)?.passwordPolicyGenerateAPIEndpoint
    }

    public func passwordPolicyValidateAPIEndpoint() -> String? {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        return NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId)?.passwordPolicyValidateAPIEndpoint
    }

    public func passwordPolicyMinLength() -> Int {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        if let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId) {
            return serverCapabilities.passwordPolicyMinLength
        }
        return -1
    }

    // MARK: - Push Notifications

    public func subscribeForPushNotifications(forAccountId accountId: String, withCompletionBlock block: ((_ success: Bool) -> Void)?) {
#if !targetEnvironment(simulator)
        var keyPair: NCPushNotificationKeyPair?
        let pushNotificationPublicKey = NCKeyChainController.sharedInstance().pushNotificationPublicKey(forAccountId: accountId)
        let pushNotificationPrivateKey = NCKeyChainController.sharedInstance().pushNotificationPrivateKey(forAccountId: accountId)

        if let pushNotificationPublicKey, let pushNotificationPrivateKey {
            keyPair = NCPushNotificationKeyPair(privateKey: pushNotificationPrivateKey, publicKey: pushNotificationPublicKey)
        } else {
            keyPair = NCPushNotificationsUtils.generatePushNotificationKeyPair()
        }

        guard let keyPair else {
            NCLog.log("Error while subscribing: Unable to generate push notifications key pair.")
            block?(false)
            return
        }

        guard NCKeyChainController.sharedInstance().combinedPushToken() != nil else {
            NCLog.log("Error while subscribing: Push token is not available.")
            block?(false)
            return
        }

        let bgTask = BGTaskHelper.startBackgroundTask(withName: "PushProxySubscription")

        NCAPIController.sharedInstance().subscribeAccount(NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId), withPublicKey: keyPair.publicKey, toNextcloudServerWithCompletionBlock: { responseDict, error in
            guard error == nil else {
                NCLog.log("Error while subscribing to NC server. Error: \(error?.description ?? "")")
                block?(false)
                bgTask.stopBackgroundTask()
                return
            }

            NCLog.log("Subscribed to NC server successfully.")

            guard let publicKey = responseDict?["publicKey"] as? String,
                  let deviceIdentifier = responseDict?["deviceIdentifier"] as? String,
                  let signature = responseDict?["signature"] as? String
            else {
                NCLog.log("Something went wrong subscribing to NC server. Aborting subscribe to Push Notification server.")
                block?(false)
                bgTask.stopBackgroundTask()
                return
            }

            let realm = RLMRealm.default()
            realm.beginWriteTransaction()
            let managedAccount = TalkAccount.objects(where: "accountId = %@", accountId).firstObject() as? TalkAccount
            managedAccount?.userPublicKey = publicKey
            managedAccount?.deviceIdentifier = deviceIdentifier
            managedAccount?.deviceSignature = signature
            try? realm.commitWriteTransaction()

            NCAPIController.sharedInstance().subscribeAccount(NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId), toPushServerWithCompletionBlock: { error in
                guard error == nil else {
                    NCLog.log("Error while subscribing to Push Notification server. Error: \(error?.localizedDescription ?? "")")
                    NCLog.log("Push notification, public key: \(publicKey)")
                    NCLog.log("Push notification, device signature: \(signature)")
                    NCLog.log("Push notification, device identifier: \(deviceIdentifier)")
                    NCKeyChainController.sharedInstance().logCombinedPushToken()
                    block?(false)
                    bgTask.stopBackgroundTask()
                    return
                }

                let realm = RLMRealm.default()
                realm.beginWriteTransaction()
                let managedAccount = TalkAccount.objects(where: "accountId = %@", accountId).firstObject() as? TalkAccount
                managedAccount?.lastPushSubscription = Int(Date().timeIntervalSince1970)
                try? realm.commitWriteTransaction()
                NCKeyChainController.sharedInstance().setPushNotificationPublicKey(keyPair.publicKey, forAccountId: accountId)
                NCKeyChainController.sharedInstance().setPushNotificationPrivateKey(keyPair.privateKey, forAccountId: accountId)
                NCLog.log("Subscribed to Push Notification server successfully.")
                block?(true)
                bgTask.stopBackgroundTask()
            })
        })
#else
        block?(true)
#endif
    }
}
