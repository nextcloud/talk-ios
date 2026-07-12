//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import PushKit
import Intents
import UserNotifications
import BackgroundTasks
import SDWebImage
import UICKeyChainStore

@objc(AppDelegate)
@objcMembers
@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, PKPushRegistryDelegate {

    public var window: UIWindow?

    public var shouldLockInterfaceOrientation: Bool = false {
        didSet {
            lockedInterfaceOrientation = UIApplication.shared.statusBarOrientation
        }
    }

    public var lockedInterfaceOrientation: UIInterfaceOrientation = .unknown

    private var pushRegistry: PKPushRegistry?
    private var normalPushToken: String?
    private var pushKitToken: String?

    private var keepAliveTimer: Timer?
    private var keepAliveBGTask: BGTaskHelper?
    private var debugLabel: UILabel?
    private var debugLabelTimer: Timer?
    private var fileDescriptorTimer: Timer?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        #if DEBUG
        AFNetworkActivityIndicatorManager.shared().isEnabled = true
        #endif
        AFNetworkReachabilityManager.shared().startMonitoring()

        NCNotificationController.sharedInstance().requestAuthorization()

        application.registerForRemoteNotifications()

        let pushRegistry = PKPushRegistry(queue: .main)
        pushRegistry.delegate = self
        pushRegistry.desiredPushTypes = [.voIP]
        self.pushRegistry = pushRegistry

        WebRTCCommon.shared.dispatch {
            NSLog("Configure Audio Session")
            _ = NCAudioController.shared
        }

        NSLog("Configure App Settings")
        _ = NCSettingsController.sharedInstance()

        // Perform cleanup only once in app lifecycle
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 10) {
            autoreleasepool {
                NCLog.removeOldLogfiles()
                SDImageCache.shared.diskCache.removeExpiredData()
                NCSettingsController.sharedInstance().createAccountsFile()

                for account in NCDatabaseManager.sharedInstance().allAccounts() {
                    NCChatFileController(account: account).removeOldFilesFromCache()
                }
            }
        }

        let currentDevice = UIDevice.current
        NCLog.log("Starting \(Bundle.main.bundleIdentifier ?? ""), version \(NCAppBranding.getAppVersionString() ?? ""), \(currentDevice.systemName) \(currentDevice.systemVersion), model \(currentDevice.model)")

        // Init rooms manager to start receiving NSNotificationCenter notifications
        _ = NCRoomsManager.shared

        self.registerBackgroundFetchTask()
        self.registerBackgroundProcessingTask()

        NCUserInterfaceController.sharedInstance().mainViewController = self.window?.rootViewController as? NCSplitViewController
        NCUserInterfaceController.sharedInstance().roomsTableViewController = NCUserInterfaceController.sharedInstance().mainViewController.viewControllers.first?.children.first as? RoomsTableViewController
        NCUserInterfaceController.sharedInstance().mainViewController.displayModeButtonVisibility = .never

        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("-TestEnvironment") {
            let mainView: UIView = NCUserInterfaceController.sharedInstance().mainViewController.view

            let debugLabel = UILabel(frame: CGRect(x: 20, y: 30, width: 200, height: 20))
            debugLabel.font = .systemFont(ofSize: UIFont.smallSystemFontSize)
            debugLabel.translatesAutoresizingMaskIntoConstraints = false
            self.debugLabel = debugLabel

            mainView.addSubview(debugLabel)
            NSLayoutConstraint.activate([
                debugLabel.topAnchor.constraint(equalTo: mainView.safeAreaLayoutGuide.topAnchor, constant: -15),
                debugLabel.leadingAnchor.constraint(equalTo: mainView.safeAreaLayoutGuide.leadingAnchor, constant: 5),
                debugLabel.trailingAnchor.constraint(equalTo: mainView.safeAreaLayoutGuide.trailingAnchor)
            ])

            self.debugLabelTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.debugLabel?.text = AllocationTracker.shared.description
            }
        }

        // Comment out the following code to log the number of open socket file descriptors
        /*
         self.fileDescriptorTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            WebRTCCommon.shared.printNumberOfOpenSocketDescriptors()
        }
         */

        // When we include VLCKit we need to manually call this because otherwise, device rotation might not work
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

        return true
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        let intent = userActivity.interaction?.intent
        let audioCallIntent = intent is INStartAudioCallIntent
        let videoCallIntent = intent is INStartVideoCallIntent
        if audioCallIntent || videoCallIntent {
            let contacts = (intent as? INStartAudioCallIntent)?.contacts ?? (intent as? INStartVideoCallIntent)?.contacts
            let person = contacts?.first
            if let roomToken = person?.personHandle?.value {
                NCUserInterfaceController.sharedInstance().presentCallKitCallInRoom(roomToken, withVideoEnabled: videoCallIntent)
            }
        }

        // A INSendMessageIntent is usually a Siri/Shortcut suggestion and automatically created when we donate a INSendMessageIntent
        if let intent = intent as? INSendMessageIntent {
            // For a INSendMessageIntent we don't receive a conversationIdentifier, see NCIntentController
            let recipient = intent.recipients?.first

            if let customIdentifier = recipient?.customIdentifier, !customIdentifier.isEmpty {
                if let room = NCDatabaseManager.sharedInstance().room(withInternalId: customIdentifier) {
                    NCRoomsManager.shared.startChat(inRoom: room)
                }
            }
        }

        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.

        self.keepExternalSignalingConnectionAliveTemporarily()
        self.scheduleAppRefresh()
        self.scheduleBackgroundProcessing()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.

        self.checkForDisconnectedExternalSignalingConnection()

        NCNotificationController.sharedInstance().removeAllNotifications(forAccountId: NCDatabaseManager.sharedInstance().activeAccount().accountId)
    }

    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        if CallKitManager.sharedInstance().calls.count > 0 {
            NCLog.log("Protected data did become available")
        }
    }

    func applicationProtectedDataWillBecomeUnavailable(_ application: UIApplication) {
        if CallKitManager.sharedInstance().calls.count > 0 {
            NCLog.log("Protected data did become unavailable")
        }
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        UIDevice.current.endGeneratingDeviceOrientationNotifications()

        // Invalidate a potentially existing label timer
        self.debugLabelTimer?.invalidate()

        self.fileDescriptorTimer?.invalidate()
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard let urlComponents = NSURLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        let scheme = urlComponents.scheme
        if scheme == "nextcloudtalk" {
            let action = urlComponents.host
            if action == "open-conversation" {
                NCUserInterfaceController.sharedInstance().presentChatForURL(urlComponents)
                return true
            } else if action == "login", multiAccountEnabled.boolValue {
                let queryItems = (urlComponents.queryItems ?? []) as NSArray
                let server = NCUtils.value(forKey: "server", fromQueryItems: queryItems)
                let user = NCUtils.value(forKey: "user", fromQueryItems: queryItems)

                if let server {
                    NCUserInterfaceController.sharedInstance().presentLoginViewController(forServerURL: server, withUser: user)
                }
                return true
            }
        }

        return false
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        if shouldLockInterfaceOrientation {
            if lockedInterfaceOrientation == .portrait {
                return .portrait
            } else if lockedInterfaceOrientation == .landscapeLeft {
                return .landscapeLeft
            } else if lockedInterfaceOrientation == .landscapeRight {
                return .landscapeRight
            }
        }
        return .allButUpsideDown
    }

    // MARK: - Push Notifications Registration

    private func checkForPushNotificationSubscription() {
        guard let normalPushToken, let pushKitToken else {
            return
        }

        // Store new Normal Push & PushKit tokens in Keychain
        let keychain = UICKeyChainStore(service: bundleIdentifier, accessGroup: groupIdentifier)
        keychain.setString(normalPushToken, forKey: kNCNormalPushTokenKey)
        keychain.setString(pushKitToken, forKey: kNCPushKitTokenKey)

        let isAppInBackground = UIApplication.shared.applicationState == .background
        // Subscribe only if both tokens have been generated and app is not running in the background (do not try to subscribe
        // when the app is running in background e.g. when the app is launched due to a VoIP push notification)
        if !isAppInBackground {
            // Try to subscribe for push notifications in all accounts
            for account in NCDatabaseManager.sharedInstance().allAccounts() {
                NCSettingsController.sharedInstance().subscribeForPushNotifications(forAccountId: account.accountId, withCompletionBlock: nil)
            }
        }
    }

    // MARK: - Normal Push Notifications Delegate Methods

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        if deviceToken.isEmpty {
            NSLog("Failed to create Normal Push token.")
            return
        }

        normalPushToken = self.string(withDeviceToken: deviceToken)
        self.checkForPushNotificationSubscription()
        self.registerInteractivePushNotification()
    }

    private func registerInteractivePushNotification() {
        // Reply directly to a chat notification action/category
        let replyAction = UNTextInputNotificationAction(identifier: NCNotificationController.actionReplyToChat,
                                                         title: NSLocalizedString("Reply", comment: ""),
                                                         options: .authenticationRequired)

        let chatCategory = UNNotificationCategory(identifier: "CATEGORY_CHAT",
                                                  actions: [replyAction],
                                                  intentIdentifiers: [],
                                                  options: [])

        // Recording actions/category
        let recordingShareAction = UNNotificationAction(identifier: NCNotificationController.actionShareRecording,
                                                        title: NSLocalizedString("Share to chat", comment: ""),
                                                        options: .authenticationRequired)

        let recordingDismissAction = UNNotificationAction(identifier: NCNotificationController.actionDismissRecordingNotification,
                                                         title: NSLocalizedString("Dismiss notification", comment: ""),
                                                         options: [.authenticationRequired, .destructive])

        let recordingCategory = UNNotificationCategory(identifier: "CATEGORY_RECORDING",
                                                       actions: [recordingShareAction, recordingDismissAction],
                                                       intentIdentifiers: [],
                                                       options: [])

        // Federation invitation
        let federationAccept = UNNotificationAction(identifier: NCNotificationController.actionFederationInvitationAccept,
                                                    title: NSLocalizedString("Accept", comment: ""),
                                                    options: .authenticationRequired)

        let federationReject = UNNotificationAction(identifier: NCNotificationController.actionFederationInvitationReject,
                                                    title: NSLocalizedString("Reject", comment: ""),
                                                    options: [.authenticationRequired, .destructive])

        let federationCategory = UNNotificationCategory(identifier: "CATEGORY_FEDERATION",
                                                        actions: [federationAccept, federationReject],
                                                        intentIdentifiers: [],
                                                        options: [])

        let categories: Set = [chatCategory, recordingCategory, federationCategory]
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Called when a background notification is delivered.
        let message = userInfo["subject"] as? String
        let signature = userInfo["signature"] as? String

        guard let message, let signature else {
            return
        }

        for account in NCDatabaseManager.sharedInstance().allAccounts() {
            if let decryptedMessage = NCPushNotificationsUtils.decryptPushNotification(withMessageBase64: message, withSignatureBase64: signature, forAccount: account) {
                let pushNotification = NCPushNotification(fromDecryptedString: decryptedMessage, withAccountId: account.accountId)
                NCNotificationController.sharedInstance().processBackgroundPushNotification(pushNotification)

                break
            }
        }

        // Check if the other notifications are still current and try to remove them otherwise
        NCNotificationController.sharedInstance().checkNotificationExistance { error in
            completionHandler(.newData)
        }
    }

    // MARK: - PushKit Delegate Methods

    func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
        if credentials.token.isEmpty {
            NSLog("Failed to create PushKit token.")
            return
        }

        pushKitToken = self.string(withDeviceToken: credentials.token)
        self.checkForPushNotificationSubscription()
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        NCLog.log("Received PushKit notification")

        let message = payload.dictionaryPayload["subject"] as? String
        let signature = payload.dictionaryPayload["signature"] as? String

        if let message, let signature {
            for account in NCDatabaseManager.sharedInstance().allAccounts() {
                guard let decryptedMessage = NCPushNotificationsUtils.decryptPushNotification(withMessageBase64: message, withSignatureBase64: signature, forAccount: account) else {
                    continue
                }

                let pushNotification = NCPushNotification(fromDecryptedString: decryptedMessage, withAccountId: account.accountId)

                if let pushNotification, pushNotification.type == .call {
                    NCNotificationController.sharedInstance().showIncomingCall(forPushNotification: pushNotification)
                    completion()
                    return
                }
            }
        }

        NCNotificationController.sharedInstance().showIncomingCallForOldAccount()
        NCSettingsController.sharedInstance().setDidReceiveCallsFromOldAccount(true)
        completion()
    }

    private func string(withDeviceToken deviceToken: Data) -> String {
        return deviceToken.map { String(format: "%02.2hhX", $0) }.joined()
    }

    // MARK: - BackgroundProcessing

    private func registerBackgroundProcessingTask() {
        let processingTaskIdentifier = "\(Bundle.main.bundleIdentifier ?? "").processing"

        // see: https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler?language=objc
        BGTaskScheduler.shared.register(forTaskWithIdentifier: processingTaskIdentifier, using: nil) { task in
            self.handleBackgroundProcessing(task)
        }
    }

    private func scheduleBackgroundProcessing() {
        let processingTaskIdentifier = "\(Bundle.main.bundleIdentifier ?? "").processing"

        let request = BGProcessingTaskRequest(identifier: processingTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: UIApplication.backgroundFetchIntervalMinimum)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            NSLog("Failed to submit background processing request: \(error)")
        }
    }

    private func handleBackgroundProcessing(_ task: BGTask) {
        NCLog.log("Performing background processing -> handleBackgroundProcessing")

        // With BGTasks (iOS >= 13) we need to schedule another task when running in background
        self.scheduleBackgroundProcessing()

        let bgTask = BGTaskHelper.startBackgroundTask(withName: "NCBackgroundProcessing") { _ in
            NCLog.log("ExpirationHandler NCBackgroundProcessing called")
        }

        // Check if the shown notifications are still available on the server
        NCNotificationController.sharedInstance().checkNotificationExistance { error in
            NCLog.log("CompletionHandler checkNotificationExistance")

            task.setTaskCompleted(success: true)
            bgTask.stopBackgroundTask()
        }
    }

    // MARK: - BackgroundFetch / AppRefresh

    private func registerBackgroundFetchTask() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let refreshTaskIdentifier = "\(bundleIdentifier).refresh"

        // see: https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler?language=objc
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskIdentifier, using: nil) { task in
            self.handleAppRefresh(task)
        }
    }

    private func scheduleAppRefresh() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let refreshTaskIdentifier = "\(bundleIdentifier).refresh"

        let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: UIApplication.backgroundFetchIntervalMinimum)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            NSLog("Failed to submit apprefresh request: \(error)")
        }
    }

    private func handleAppRefresh(_ task: BGTask) {
        NCLog.log("Performing background fetch -> handleAppRefresh")

        // With BGTasks (iOS >= 13) we need to schedule another refresh when running in background
        self.scheduleAppRefresh()

        self.performBackgroundFetch { errorOccurred in
            task.setTaskCompleted(success: !errorOccurred)
        }
    }

    // This method is called when you simulate a background fetch from the debug menu in XCode
    // so we keep it around, although it's deprecated on iOS 13 onwards
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        NCLog.log("Performing background fetch -> performFetchWithCompletionHandler")

        self.performBackgroundFetch { errorOccurred in
            if errorOccurred {
                completionHandler(.failed)
            } else {
                completionHandler(.newData)
            }
        }
    }

    private func performBackgroundFetch(withCompletionHandler completionHandler: @escaping (_ errorOccurred: Bool) -> Void) {
        let backgroundRefreshGroup = DispatchGroup()
        var errorOccurred = false
        var expired = false

        let bgTask = BGTaskHelper.startBackgroundTask(withName: "NCBackgroundFetch") { _ in
            NCLog.log("ExpirationHandler called")

            /*
            expired = true
            completionHandler(true)

            task.stopBackgroundTask()
             */
        }

        NCLog.log("Start performBackgroundFetchWithCompletionHandler")

        backgroundRefreshGroup.enter()
        NCRoomsManager.shared.resendOfflineMessagesWithCompletionBlock {
            NCLog.log("CompletionHandler resendOfflineMessagesWithCompletionBlock")

            backgroundRefreshGroup.leave()
        }

        // Check if the shown notifications are still available on the server
        backgroundRefreshGroup.enter()
        NCNotificationController.sharedInstance().checkNotificationExistance { error in
            NCLog.log("CompletionHandler checkNotificationExistance")

            if error != nil {
                errorOccurred = true
            }

            backgroundRefreshGroup.leave()
        }

        backgroundRefreshGroup.enter()
        NCRoomsManager.shared.updateRoomsAndChats(updatingUserStatus: false, onlyLastModified: true) { error in
            NCLog.log("CompletionHandler updateRoomsAndChatsUpdatingUserStatus")

            if error != nil {
                errorOccurred = true
            }

            backgroundRefreshGroup.leave()
        }

        var dayComponent = DateComponents()
        dayComponent.day = -1

        let thresholdDate = Calendar.current.date(byAdding: dayComponent, to: Date())
        let thresholdTimestamp = Int(thresholdDate?.timeIntervalSince1970 ?? 0)

        // Push proxy should be subscrided atleast every 24h
        // Check if we reached the threshold and start the subscription process
        for account in NCDatabaseManager.sharedInstance().allAccounts() {
            if account.lastPushSubscription < thresholdTimestamp {
                backgroundRefreshGroup.enter()

                NCSettingsController.sharedInstance().subscribeForPushNotifications(forAccountId: account.accountId) { success in
                    if !success {
                        errorOccurred = true
                    }

                    backgroundRefreshGroup.leave()
                }
            }
        }

        backgroundRefreshGroup.notify(queue: .main) {
            NCLog.log("CompletionHandler performBackgroundFetchWithCompletionHandler dispatch_group_notify")

            if !expired {
                completionHandler(errorOccurred)
            }

            bgTask.stopBackgroundTask()
        }
    }

    func keepExternalSignalingConnectionAliveTemporarily() {
        keepAliveTimer?.invalidate()

        keepAliveBGTask = BGTaskHelper.startBackgroundTask(withName: "NCWebSocketKeepAlive", expirationHandler: nil)
        let keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { _ in
            // Stop the external signaling connections only if the app keeps in the background and not in a call
            if UIApplication.shared.applicationState == .background,
               NCRoomsManager.shared.callViewController == nil {
                NCSettingsController.sharedInstance().disconnectAllExternalSignalingControllers()
            }

            // Disconnect is dispatched to the main queue, so in theory it can happen that we stop the background task
            // before the disconnect is run/completed. So we dispatch the stopBackgroundTask to main as well
            // to be sure it's called after everything else is run.
            DispatchQueue.main.async {
                self.keepAliveBGTask?.stopBackgroundTask()
            }
        }
        self.keepAliveTimer = keepAliveTimer

        RunLoop.main.add(keepAliveTimer, forMode: .common)
    }

    private func checkForDisconnectedExternalSignalingConnection() {
        keepAliveTimer?.invalidate()
        keepAliveBGTask?.stopBackgroundTask()

        NCSettingsController.sharedInstance().connectDisconnectedExternalSignalingControllers()
    }
}
