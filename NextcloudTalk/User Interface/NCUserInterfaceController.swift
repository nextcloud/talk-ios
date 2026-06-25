//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import UIKit
import JDStatusBarNotification

public typealias PresentCallControllerCompletionBlock = () -> Void

@objcMembers class NCUserInterfaceController: NSObject, LoginViewControllerDelegate, AuthenticationViewControllerDelegate {

    var mainViewController: NCSplitViewController!
    var roomsTableViewController: RoomsTableViewController!

    private var loginViewController: LoginViewController?
    private var authViewController: AuthenticationViewController?
    private var pendingPushNotification: NCPushNotification?
    private var pendingCallKitCall: [String: Any]?
    private var pendingLocalNotification: [AnyHashable: Any]?
    private var pendingURL: NSURLComponents?
    private var waitingForServerCapabilities = false

    static let shared = NCUserInterfaceController()

    class func sharedInstance() -> NCUserInterfaceController {
        return shared
    }

    override private init() {
        super.init()

        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(appStateHasChanged(_:)), name: .NCAppStateHasChangedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(connectionStateHasChanged(_:)), name: .NCConnectionStateHasChangedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(presentTalkNotInstalledWarningAlert), name: .NCTalkNotInstalled, object: nil)
        notificationCenter.addObserver(self, selector: #selector(presentTalkOutdatedWarningAlert), name: .NCOutdatedTalkVersion, object: nil)
        notificationCenter.addObserver(self, selector: #selector(presentServerMaintenanceModeWarning(_:)), name: .NCServerMaintenanceMode, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func presentLoginViewController() {
        presentLoginViewController(forServerURL: nil, withUser: nil)
    }

    func presentLoginViewController(forServerURL serverURL: String?, withUser user: String?) {
        if forceDomain.boolValue, let authViewController = AuthenticationViewController(serverUrl: domain) {
            authViewController.delegate = self
            authViewController.modalPresentationStyle = NCDatabaseManager.sharedInstance().numberOfAccounts() == 0 ? .fullScreen : .automatic
            self.authViewController = authViewController
            mainViewController.present(authViewController, animated: true)
        } else {
            // Don't open a login if we're in a call
            if NCRoomsManager.shared.callViewController != nil {
                return
            }

            // Leave chat if we're currently in one
            if NCRoomsManager.shared.chatViewController != nil {
                presentConversationsList()
            }

            if loginViewController == nil || mainViewController.presentedViewController != loginViewController {
                let loginViewController = LoginViewController()
                loginViewController.delegate = self
                loginViewController.modalPresentationStyle = NCDatabaseManager.sharedInstance().numberOfAccounts() == 0 ? .fullScreen : .automatic
                self.loginViewController = loginViewController

                mainViewController.present(loginViewController, animated: true)
            }

            if let serverURL {
                loginViewController?.startLoginProcess(serverURL: serverURL, user: user)
            }
        }
    }

    func presentLoggedOutInvalidCredentialsAlert() {
        let alert = UIAlertController(title: NSLocalizedString("Logged out", comment: ""),
                                      message: NSLocalizedString("Credentials for this account were no longer valid", comment: ""),
                                      preferredStyle: .alert)

        let okButton = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { _ in
            // Check the app state here, as this alert may have blocked the login view from being presented (if no other accounts are configured)
            NCConnectionController.shared.checkAppState()
        }

        alert.addAction(okButton)
        mainViewController.present(alert, animated: true)
    }

    func presentOfflineWarningAlert() {
        let alert = UIAlertController(title: NSLocalizedString("Disconnected", comment: ""),
                                      message: NSLocalizedString("It seems that there is no internet connection.", comment: ""),
                                      preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        mainViewController.present(alert, animated: true)
    }

    func presentTalkNotInstalledWarningAlert() {
        let alert = UIAlertController(title: String(format: NSLocalizedString("%@ not installed", comment: "{app name} is not installed"), talkAppName),
                                      message: String(format: NSLocalizedString("It seems that %@ is not installed in your server.", comment: "It seems that {app name} is not installed in your server."), talkAppName),
                                      preferredStyle: .alert)

        let okButton = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { [weak self] _ in
            self?.logOutCurrentUser()
        }

        alert.addAction(okButton)
        mainViewController.present(alert, animated: true)
    }

    func presentTalkOutdatedWarningAlert() {
        let alert = UIAlertController(title: String(format: NSLocalizedString("%@ version not supported", comment: "{app name} version not supported"), talkAppName),
                                      message: String(format: NSLocalizedString("Please update your server with the latest %@ version available.", comment: "Please update your server with the latest {app name} version available."), talkAppName),
                                      preferredStyle: .alert)

        let okButton = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { [weak self] _ in
            self?.logOutCurrentUser()
        }

        alert.addAction(okButton)
        mainViewController.present(alert, animated: true)
    }

    func presentAccountNotConfiguredAlert(forUser user: String?, inServer server: String?) {
        let alert = UIAlertController(title: NSLocalizedString("Account not configured", comment: ""),
                                      message: String(format: NSLocalizedString("There is no account for user %@ in server %@ configured in this app.", comment: ""), user ?? "", server ?? ""),
                                      preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        mainViewController.present(alert, animated: true)
    }

    func presentServerMaintenanceModeWarning(_ notification: Notification) {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let accountId = notification.userInfo?["accountId"] as? String

        if let accountId, activeAccount.accountId == accountId {
            NotificationPresenter.shared().present(text: NSLocalizedString("Server is currently in maintenance mode", comment: ""), dismissAfterDelay: 4.0, includedStyle: .error)
        }
    }

    func logOutAccount(withAccountId accountId: String) {
        NCSettingsController.sharedInstance().logoutAccount(withAccountId: accountId) { _ in
            NCUserInterfaceController.sharedInstance().presentConversationsList()
            NCConnectionController.shared.checkAppState()
        }
    }

    func logOutCurrentUser() {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        logOutAccount(withAccountId: activeAccount.accountId)
    }

    func presentChat(forLocalNotification userInfo: [AnyHashable: Any]) {
        if NCConnectionController.shared.appState != .ready {
            waitingForServerCapabilities = true
            pendingLocalNotification = userInfo
            return
        }

        NotificationCenter.default.post(name: .NCLocalNotificationJoinChat, object: self, userInfo: userInfo)
    }

    func presentChat(for pushNotification: NCPushNotification) {
        if NCConnectionController.shared.appState != .ready {
            waitingForServerCapabilities = true
            pendingPushNotification = pushNotification
            return
        }

        let userInfo = ["pushNotification": pushNotification]
        NotificationCenter.default.post(name: .NCPushNotificationJoinChat, object: self, userInfo: userInfo)
    }

    func presentAlert(for pushNotification: NCPushNotification) {
        if NCConnectionController.shared.appState != .ready {
            waitingForServerCapabilities = true
            pendingPushNotification = pushNotification
            return
        }

        let alert = UIAlertController(title: pushNotification.bodyForRemoteAlerts(),
                                      message: NSLocalizedString("Do you want to join this call?", comment: ""),
                                      preferredStyle: .alert)

        let joinAudioButton = UIAlertAction(title: NSLocalizedString("Join call (audio only)", comment: ""), style: .default) { _ in
            let userInfo = ["pushNotification": pushNotification]
            NotificationCenter.default.post(name: .NCPushNotificationJoinAudioCallAccepted, object: self, userInfo: userInfo)
        }

        let joinVideoButton = UIAlertAction(title: NSLocalizedString("Join call with video", comment: ""), style: .default) { _ in
            let userInfo = ["pushNotification": pushNotification]
            NotificationCenter.default.post(name: .NCPushNotificationJoinVideoCallAccepted, object: self, userInfo: userInfo)
        }

        let cancelButton = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel)

        joinAudioButton.setValue(UIImage(systemName: "phone"), forKey: "image")
        joinVideoButton.setValue(UIImage(systemName: "video"), forKey: "image")

        alert.addAction(joinAudioButton)
        alert.addAction(joinVideoButton)
        alert.addAction(cancelButton)

        // Do not show join call dialog until we don't handle 'hangup current call'/'join new one' properly.
        if NCRoomsManager.shared.callViewController == nil {
            mainViewController.dismiss(animated: false)
            mainViewController.present(alert, animated: true)
        } else {
            NSLog("Not showing join call dialog due to in a call.")
        }
    }

    func presentAlertViewController(_ alertViewController: UIAlertController) {
        if let presentedViewController = mainViewController.presentedViewController, !presentedViewController.isBeingDismissed {
            // When the callview is presented, we need to show the alert this way
            presentedViewController.present(alertViewController, animated: true)
        } else {
            mainViewController.present(alertViewController, animated: true)
        }
    }

    func presentAlertIfNotPresentedAlready(_ alertViewController: UIAlertController) {
        if alertViewController != mainViewController.presentedViewController {
            presentAlertViewController(alertViewController)
        }
    }

    func presentAlert(withTitle title: String, withMessage message: String?) {
        let alertDialog = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertDialog.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        presentAlertViewController(alertDialog)
    }

    func presentConversationsList() {
        mainViewController.dismiss(animated: true) { [weak self] in
            self?.popToConversationsList()
        }
    }

    func popToConversationsList() {
        mainViewController.popSecondaryColumnToRootViewController()
        mainViewController.show(.primary)
    }

    func present(_ chatViewController: ChatViewController) {
        // Present conversation list first (see presentConversationsList)
        mainViewController.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.popToConversationsList()

            self.mainViewController.showDetailViewController(chatViewController, sender: self)
            self.roomsTableViewController.selectedRoomToken = chatViewController.room.token
        }
    }

    func present(_ callViewController: CallViewController, completionBlock block: PresentCallControllerCompletionBlock?) {
        mainViewController.dismiss(animated: false)
        mainViewController.present(callViewController, animated: true) {
            block?()
        }
    }

    func presentCallKitCallInRoom(_ token: String, withVideoEnabled video: Bool) {
        var userInfo: [String: Any] = ["roomToken": token]
        userInfo["isVideoEnabled"] = video
        if NCConnectionController.shared.appState != .ready {
            waitingForServerCapabilities = true
            pendingCallKitCall = userInfo
            return
        }
        startCallKitCall(userInfo)
    }

    func startCallKitCall(_ callDict: [String: Any]) {
        guard let roomToken = callDict["roomToken"] as? String else { return }
        let video = (callDict["isVideoEnabled"] as? Bool) ?? false
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCRoomsManager.shared.joinCall(withCallToken: roomToken, withAccountId: activeAccount.accountId, withVideo: video, asInitiator: true, silently: false, recordingConsent: false)
    }

    func presentChatForURL(_ urlComponents: NSURLComponents) {
        if NCConnectionController.shared.appState != .ready {
            waitingForServerCapabilities = true
            pendingURL = urlComponents
            return
        }

        let queryItems = (urlComponents.queryItems ?? []) as NSArray
        let server = NCUtils.value(forKey: "server", fromQueryItems: queryItems)
        let user = NCUtils.value(forKey: "user", fromQueryItems: queryItems)
        let withUser = NCUtils.value(forKey: "withUser", fromQueryItems: queryItems)
        let withRoomToken = NCUtils.value(forKey: "withRoomToken", fromQueryItems: queryItems)
        let account = NCDatabaseManager.sharedInstance().talkAccount(forUserId: user ?? "", inServer: server ?? "")

        guard let account else {
            presentAccountNotConfiguredAlert(forUser: user, inServer: server)
            return
        }

        var userInfo: [String: Any] = ["accountId": account.accountId]
        if let withUser {
            userInfo["withUser"] = withUser
        } else if let withRoomToken {
            userInfo["withRoomToken"] = withRoomToken
        } else {
            return
        }

        NotificationCenter.default.post(name: .NCURLWantsToOpenConversation, object: self, userInfo: userInfo)
    }

    func presentSettingsViewController() {
        presentConversationsList()
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let settingsNC = storyboard.instantiateViewController(withIdentifier: "settingsNC")
        mainViewController.present(settingsNC, animated: true)
    }

    func presentShareLinkDialog(for room: NCRoom, inViewContoller viewController: UITableViewController?, for indexPath: IndexPath?) {
        guard let roomLinkURL = room.linkURL else {
            return
        }

        let items = [roomLinkURL]
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)

        let emailSubject = String(format: NSLocalizedString("%@ invitation", comment: ""), talkAppName)
        controller.setValue(emailSubject, forKey: "subject")

        // Presentation on iPads
        if let viewController, let indexPath {
            controller.popoverPresentationController?.sourceView = viewController.tableView
            controller.popoverPresentationController?.sourceRect = viewController.tableView.rectForRow(at: indexPath)
        }

        if let viewController {
            viewController.present(controller, animated: true)
        } else {
            mainViewController.present(controller, animated: true)
        }

        controller.completionWithItemsHandler = { _, _, _, error in
            if let error {
                NSLog("An Error occured sharing room: %@, %@", error.localizedDescription, (error as NSError).localizedFailureReason ?? "")
            }
        }
    }

    func presentVoiceRoomJoinAlert(for room: NCRoom) {
        let alert = UIAlertController(title: room.displayName,
                                      message: NSLocalizedString("How do you want to join the call?", comment: ""),
                                      preferredStyle: .actionSheet)

        let audioAction = UIAlertAction(title: NSLocalizedString("Audio only", comment: "Join a call in audio only mode"), style: .default) { _ in
            self.startCall(in: room, withVideo: false)
        }

        let videoAction = UIAlertAction(title: NSLocalizedString("Video call", comment: "Join a call in video call mode"), style: .default) { _ in
            self.startCall(in: room, withVideo: true)
        }

        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel)

        audioAction.setValue(UIImage(systemName: "mic"), forKey: "image")
        videoAction.setValue(UIImage(systemName: "video"), forKey: "image")

        alert.addAction(audioAction)
        alert.addAction(videoAction)
        alert.addAction(cancelAction)

        presentAlertViewController(alert)
    }

    private func startCall(in room: NCRoom, withVideo video: Bool) {
        let startCall = {
            CallKitManager.sharedInstance().startCall(room.token, withVideoEnabled: video, andDisplayName: room.displayName, asInitiator: true, silently: true, recordingConsent: true, withAccountId: room.account?.accountId ?? "")
        }

        if room.recordingConsent {
            presentRecordingConsentAlert(for: room) { confirmed in
                if confirmed {
                    startCall()
                }
            }
        } else {
            startCall()
        }
    }

    func presentRecordingConsentAlert(for room: NCRoom, confirmed completion: ((Bool) -> Void)?) {
        let title = "⚠️ " + NSLocalizedString("The call might be recorded", comment: "")
        let message = NSLocalizedString("The recording might include your voice, video from camera, and screen share. Your consent is required before joining the call.", comment: "")

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)

        let joinAction = UIAlertAction(title: NSLocalizedString("Give consent and join call", comment: "Give consent to the recording of the call and join that call"), style: .default) { _ in
            completion?(true)
        }

        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
            completion?(false)
        }

        alert.addAction(joinAction)
        alert.addAction(cancelAction)

        presentAlertViewController(alert)
    }

    // MARK: - Notifications

    func appStateHasChanged(_ notification: Notification) {
        guard let rawAppState = notification.userInfo?["appState"] as? Int, let appState = AppState(rawValue: rawAppState) else {
            return
        }

        if appState == .ready, waitingForServerCapabilities {
            waitingForServerCapabilities = false

            if let pendingPushNotification {
                if pendingPushNotification.type == .call {
                    presentAlert(for: pendingPushNotification)
                } else {
                    presentChat(for: pendingPushNotification)
                }
            } else if let pendingCallKitCall {
                startCallKitCall(pendingCallKitCall)
            } else if let pendingURL {
                presentChatForURL(pendingURL)
            }
        }
    }

    func connectionStateHasChanged(_ notification: Notification) {
        guard let rawConnectionState = notification.userInfo?["connectionState"] as? Int, let connectionState = ConnectionState(rawValue: rawConnectionState) else {
            return
        }

        switch connectionState {
        case .disconnected:
            NotificationPresenter.shared().present(text: NSLocalizedString("Network not available", comment: ""), dismissAfterDelay: 4.0, includedStyle: .error)
        case .connected:
            NotificationPresenter.shared().present(text: NSLocalizedString("Network available", comment: ""), dismissAfterDelay: 4.0, includedStyle: .success)
        default:
            break
        }
    }

    // MARK: - LoginViewControllerDelegate

    func loginViewControllerDidFinish() {
        mainViewController.dismiss(animated: true) {
            NCConnectionController.shared.checkAppState()
            // Get server capabilities again to check if user is allowed to use Nextcloud Talk
            let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
            NCSettingsController.sharedInstance().getCapabilitiesForAccountId(activeAccount.accountId, withCompletionBlock: nil)
        }
    }

    // MARK: - AuthenticationViewControllerDelegate

    func authenticationViewControllerDidFinish(_ viewController: AuthenticationViewController) {
        mainViewController.dismiss(animated: true) {
            NCConnectionController.shared.checkAppState()
            // Get server capabilities again to check if user is allowed to use Nextcloud Talk
            let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
            NCSettingsController.sharedInstance().getCapabilitiesForAccountId(activeAccount.accountId, withCompletionBlock: nil)
        }
    }
}
