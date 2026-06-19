//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import UserNotifications

// MARK: - Notification names

extension NSNotification.Name {
    static let NCNotificationControllerWillPresent = Notification.Name(rawValue: "NCNotificationControllerWillPresentNotification")
    static let NCLocalNotificationJoinChat = Notification.Name(rawValue: "NCLocalNotificationJoinChatNotification")
}

@objc extension NSNotification {
    public static let NCNotificationControllerWillPresent = Notification.Name.NCNotificationControllerWillPresent
    public static let NCLocalNotificationJoinChat = Notification.Name.NCLocalNotificationJoinChat
}

@objcMembers
public class NCNotificationController: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NCNotificationController()

    @available(*, renamed: "shared")
    static func sharedInstance() -> NCNotificationController {
        return NCNotificationController.shared
    }

    // MARK: - Notification action identifiers

    public static let actionShareRecording = "SHARE_RECORDING"
    public static let actionDismissRecordingNotification = "DISMISS_RECORDING_NOTIFICATION"
    public static let actionReplyToChat = "REPLY_CHAT"
    public static let actionFederationInvitationAccept = "ACCEPT_FEDERATION_INVITATION"
    public static let actionFederationInvitationReject = "REJECT_FEDERATION_INVITATION"

    private let notificationCenter = UNUserNotificationCenter.current()
    private var serverNotificationsAttempts: [AnyHashable: Any] = [:] // notificationId -> get attempts

    override init() {
        super.init()

        self.notificationCenter.delegate = self
    }

    public func requestAuthorization() {
        let authOptions: UNAuthorizationOptions = [.alert, .sound, .badge]
        self.notificationCenter.requestAuthorization(options: authOptions) { granted, _ in
            if granted {
                NSLog("User notifications permission granted.")
            } else {
                NSLog("User notifications permission denied.")
            }
        }
    }

    public func processBackgroundPushNotification(_ pushNotification: NCPushNotification?) {
        guard let pushNotification else {
            return
        }

        switch pushNotification.type {
        case .delete:
            self.removeNotification(withNotificationIds: [NSNumber(value: pushNotification.notificationId)], forAccountId: pushNotification.accountId, withCompletionBlock: nil)
        case .deleteAll:
            self.removeAllNotifications(forAccountId: pushNotification.accountId)
        case .deleteMultiple:
            self.removeNotification(withNotificationIds: pushNotification.notificationIds as? [NSNumber], forAccountId: pushNotification.accountId, withCompletionBlock: nil)
        default:
            NSLog("Push Notification of an unknown type received")
        }
    }

    @objc(showLocalNotification:withUserInfo:)
    public func show(_ type: NCLocalNotificationType, withUserInfo userInfo: [AnyHashable: Any]) {
        let content = UNMutableNotificationContent()

        switch type {
        case .missedCall:
            let missedCallString = NSLocalizedString("Missed call from", comment: "")
            content.body = "☎️ \(missedCallString) \(userInfo["displayName"] ?? "")"
            content.userInfo = userInfo
        case .cancelledCall:
            let cancelledCallString = NSLocalizedString("Cancelled call from another account", comment: "")
            content.body = "☎️ \(cancelledCallString)"
            content.userInfo = userInfo
        case .failedSendChat:
            content.body = NSLocalizedString("Failed to send message", comment: "")
            content.userInfo = userInfo
        case .callFromOldAccount:
            content.body = NSLocalizedString("Received call from an old account", comment: "")
            content.userInfo = userInfo
        case .failedToShareRecording:
            content.body = NSLocalizedString("Failed to share recording", comment: "")
            content.userInfo = userInfo
        case .failedToAcceptInvitation:
            content.body = NSLocalizedString("Failed to accept invitation", comment: "")
            content.userInfo = userInfo
        case .recordingConsentRequired:
            let consentRequiredString = NSLocalizedString("Recording consent required for joining the call", comment: "")
            content.body = "⚠️ \(consentRequiredString) \(userInfo["displayName"] ?? "")"
            content.userInfo = userInfo
        case .endToEndEncryptionUnsupported:
            let endToEndEncryptionUnsupported = NSLocalizedString("Calling is currently not supported because end-to-end-encryption is enabled on the server", comment: "")
            content.body = "⚠️ \(endToEndEncryptionUnsupported)"
            content.userInfo = userInfo
        default:
            break
        }

        let identifier = String(format: "Notification-%f", Date().timeIntervalSince1970)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        self.notificationCenter.add(request, withCompletionHandler: nil)

        let accountId = userInfo["accountId"] as? String ?? ""
        NCDatabaseManager.sharedInstance().increaseUnreadBadgeNumber(forAccountId: accountId)
        self.updateAppIconBadgeNumber()
    }

    public func showLocalNotificationForIncomingCall(withPushNotificaion pushNotification: NCPushNotification) {
        let content = UNMutableNotificationContent()
        content.body = pushNotification.bodyForRemoteAlerts()
        content.threadIdentifier = pushNotification.roomToken
        content.sound = .default

        var userInfo: [AnyHashable: Any] = [:]
        userInfo["pushNotification"] = pushNotification.jsonString
        userInfo["accountId"] = pushNotification.accountId
        userInfo["notificationId"] = pushNotification.notificationId
        content.userInfo = userInfo

        let identifier = String(format: "Notification-%f", Date().timeIntervalSince1970)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        self.notificationCenter.add(request, withCompletionHandler: nil)

        NCDatabaseManager.sharedInstance().increaseUnreadBadgeNumber(forAccountId: pushNotification.accountId)
        self.updateAppIconBadgeNumber()
    }

    public func showIncomingCall(forPushNotification pushNotification: NCPushNotification) {
        if CallKitManager.isCallKitAvailable() {
            CallKitManager.sharedInstance().reportIncomingCall(pushNotification.roomToken, withDisplayName: NSLocalizedString("Incoming call", comment: ""), forAccountId: pushNotification.accountId)
        } else {
            CallKitManager.sharedInstance().reportIncomingCallForNonCallKitDevices(withPushNotification: pushNotification)
        }
    }

    public func showIncomingCallForOldAccount() {
        CallKitManager.sharedInstance().reportIncomingCallForOldAccount()
    }

    public func showLocalNotification(forChatNotification notification: NCNotification, forAccountId accountId: String) {
        let content = UNMutableNotificationContent()
        content.title = notification.chatMessageTitle
        content.body = notification.message
        content.summaryArgument = notification.chatMessageAuthor
        content.threadIdentifier = notification.roomToken
        content.sound = .default

        // Currently not supported for local notifications
        // content.categoryIdentifier = "CATEGORY_CHAT"

        var userInfo: [AnyHashable: Any] = [:]
        userInfo["roomToken"] = notification.roomToken
        userInfo["accountId"] = accountId
        userInfo["notificationId"] = notification.notificationId
        userInfo["localNotificationType"] = NCLocalNotificationType.chatNotification.rawValue
        content.userInfo = userInfo

        let identifier = "ChatNotification-\(notification.notificationId)"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        self.notificationCenter.add(request, withCompletionHandler: nil)

        NCDatabaseManager.sharedInstance().increaseUnreadBadgeNumber(forAccountId: accountId)
        self.updateAppIconBadgeNumber()
    }

    private func updateAppIconBadgeNumber() {
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = NCDatabaseManager.sharedInstance().numberOfUnreadNotifications()
        }
    }

    public func removeAllNotifications(forAccountId accountId: String) {
        // Check in pending notifications
        self.notificationCenter.getPendingNotificationRequests { requests in
            for notificationRequest in requests {
                let notificationAccountId = notificationRequest.content.userInfo["accountId"] as? String
                if let notificationAccountId, notificationAccountId == accountId {
                    self.notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationRequest.identifier])
                }
            }
        }
        // Check in delivered notifications
        self.notificationCenter.getDeliveredNotifications { notifications in
            for notification in notifications {
                let notificationAccountId = notification.request.content.userInfo["accountId"] as? String
                if let notificationAccountId, notificationAccountId == accountId {
                    self.notificationCenter.removeDeliveredNotifications(withIdentifiers: [notification.request.identifier])
                }
            }
        }

        NCDatabaseManager.sharedInstance().resetUnreadBadgeNumber(forAccountId: accountId)
        self.updateAppIconBadgeNumber()
    }

    private func removeNotification(withNotificationIds notificationIds: [NSNumber]?, forAccountId accountId: String, withCompletionBlock completion: (() -> Void)?) {
        guard let notificationIds else {
            completion?()
            return
        }

        let bgTask = BGTaskHelper.startBackgroundTask(withName: "decreaseUnreadBadgeNumberForAccountId")

        let removeNotification: (UNNotificationRequest, Bool) -> Void = { notificationRequest, isPending in
            let notificationAccountId = notificationRequest.content.userInfo["accountId"] as? String
            let notificationId = (notificationRequest.content.userInfo["notificationId"] as? NSNumber)?.intValue ?? 0

            guard notificationAccountId == accountId else {
                return
            }

            if notificationIds.contains(NSNumber(value: notificationId)) {
                if isPending {
                    self.notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationRequest.identifier])
                } else {
                    self.notificationCenter.removeDeliveredNotifications(withIdentifiers: [notificationRequest.identifier])
                }

                NCDatabaseManager.sharedInstance().decreaseUnreadBadgeNumber(forAccountId: accountId)
            }
        }

        let notificationsGroup = DispatchGroup()

        notificationsGroup.enter()
        // Check in pending notifications
        self.notificationCenter.getPendingNotificationRequests { requests in
            for notificationRequest in requests {
                if bgTask.isExpired {
                    notificationsGroup.leave()
                    return
                }
                removeNotification(notificationRequest, true)
            }

            self.updateAppIconBadgeNumber()
            notificationsGroup.leave()
        }

        notificationsGroup.enter()
        // Check in delivered notifications
        self.notificationCenter.getDeliveredNotifications { notifications in
            for notification in notifications {
                if bgTask.isExpired {
                    notificationsGroup.leave()
                    return
                }
                removeNotification(notification.request, false)
            }

            self.updateAppIconBadgeNumber()
            notificationsGroup.leave()
        }

        notificationsGroup.notify(queue: .main) {
            completion?()
            bgTask.stopBackgroundTask()
        }
    }

    public func checkNotificationExistance(completionBlock block: ((_ error: Error?) -> Void)?) {
        let notificationsGroup = DispatchGroup()

        for account in NCDatabaseManager.sharedInstance().allAccounts() {
            if !NCDatabaseManager.sharedInstance().serverHasNotificationsCapability(kNotificationsCapabilityExists, forAccountId: account.accountId) {
                continue
            }

            notificationsGroup.enter()

            self.notificationCenter.getDeliveredNotifications { notifications in
                var notificationIdsOnDevice: [NSNumber] = []

                // TODO: Instead of storing just the IDs, we can also store the identifier and directly
                // remove the notification instead of iterating again removeNotificationWithNotificationIds
                for notification in notifications {
                    let notificationRequest = notification.request
                    let notificationAccountId = notificationRequest.content.userInfo["accountId"] as? String
                    let notificationId = (notificationRequest.content.userInfo["notificationId"] as? NSNumber)?.intValue ?? 0

                    if notificationAccountId != account.accountId {
                        continue
                    }

                    notificationIdsOnDevice.append(NSNumber(value: notificationId))
                }

                if notificationIdsOnDevice.isEmpty {
                    // No notifications for this account are currently shown on the system -> no need to check anything
                    notificationsGroup.leave()
                    return
                }

                NCAPIController.sharedInstance().checkNotificationExistance(withIds: notificationIdsOnDevice.map { $0.intValue }, forAccount: account) { notificationIds, error in
                    if error != nil {
                        notificationsGroup.leave()
                        return
                    }

                    // Remove all notificationIds which are still on the server
                    if let notificationIds {
                        for notificationId in notificationIds {
                            notificationIdsOnDevice.removeAll { $0.intValue == notificationId }
                        }
                    }

                    // In case there are still notifications on the device (that are not on the server anymore) remove them
                    if notificationIdsOnDevice.isEmpty {
                        notificationsGroup.leave()
                        return
                    }

                    self.removeNotification(withNotificationIds: notificationIdsOnDevice, forAccountId: account.accountId) {
                        notificationsGroup.leave()
                    }
                }
            }
        }

        notificationsGroup.notify(queue: .main) {
            // Notify backgroundFetch that we're finished
            block?(nil)
        }
    }

    @nonobjc
    public func checkNotificationExistance() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.checkNotificationExistance { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - UNUserNotificationCenter delegate

    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Called when a notification is delivered to a foreground app.
        NotificationCenter.default.post(name: .NCNotificationControllerWillPresent, object: self, userInfo: nil)
        completionHandler([.list, .banner])

        // Remove the notification from Notification Center if it is from the active account
        let notificationAccountId = notification.request.content.userInfo["accountId"] as? String
        if let notificationAccountId, NCDatabaseManager.sharedInstance().activeAccount().accountId == notificationAccountId {
            self.removeAllNotifications(forAccountId: notificationAccountId)
        }
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let notificationRequest = response.notification.request
        let userInfo = notificationRequest.content.userInfo

        // Local notification
        let localNotificationType = NCLocalNotificationType(rawValue: (userInfo["localNotificationType"] as? NSNumber)?.intValue ?? 0)

        // Push notification
        let notificationString = userInfo["pushNotification"] as? String
        let notificationAccountId = userInfo["accountId"] as? String
        var pushNotification: NCPushNotification?
        if let notificationString {
            pushNotification = NCPushNotification(fromDecryptedString: notificationString, withAccountId: notificationAccountId)
        }

        // Server notification (only available if the Notification Service Extension was able to fetch it)
        let serverNotificationDict = userInfo["serverNotification"] as? [String: Any]
        let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: notificationAccountId ?? "")
        let serverNotification = NCNotification(dictionary: serverNotificationDict)

        // Update push notification with server notification
        pushNotification?.threadId = serverNotification?.threadId ?? 0

        // Handle notification response
        if let pushNotification {
            if let textInputResponse = response as? UNTextInputNotificationResponse {
                pushNotification.responseUserText = textInputResponse.userText
                self.handlePushNotificationResponse(withUserText: pushNotification)
            } else if pushNotification.type == .recording {
                self.handlePushNotificationResponseForRecording(serverNotification, withActionIdentifier: response.actionIdentifier, forAccount: account)
            } else if pushNotification.type == .federation {
                self.handlePushNotificationResponseForFederation(serverNotification, withActionIdentifier: response.actionIdentifier, forAccount: account)
            } else if pushNotification.type == .reminder {
                self.handlePushNotificationResponseForReminder(serverNotification, withActionIdentifier: response.actionIdentifier, forAccount: account)
            } else {
                self.handlePushNotificationResponse(pushNotification)
            }
        } else if let localNotificationType, localNotificationType.rawValue > 0 {
            self.handleLocalNotificationResponse(notificationRequest.content.userInfo)
        }

        completionHandler()
    }

    private func handlePushNotificationResponse(withUserText pushNotification: NCPushNotification) {
        NSLog("Received push-notification with user input -> sending chat message")

        guard let pushAccount = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: pushNotification.accountId) else {
            return
        }

        let application = UIApplication.shared
        var sendTask: UIBackgroundTaskIdentifier = .invalid
        sendTask = application.beginBackgroundTask {
            application.endBackgroundTask(sendTask)
            sendTask = .invalid
        }

        DispatchQueue.global().async {
            NCAPIController.sharedInstance().sendChatMessage(pushNotification.responseUserText, toRoom: pushNotification.roomToken, threadTitle: nil, replyTo: -1, referenceId: nil, silently: false, forAccount: pushAccount) { error in
                if let error {
                    NSLog("Could not send chat message. Error: %@", error.description)

                    // Display local push-notification to inform user
                    var userInfo: [AnyHashable: Any] = [:]
                    userInfo["roomToken"] = pushNotification.roomToken
                    userInfo["localNotificationType"] = NCLocalNotificationType.failedSendChat.rawValue
                    userInfo["accountId"] = pushNotification.accountId
                    userInfo["responseUserText"] = pushNotification.responseUserText

                    NCNotificationController.sharedInstance().show(.failedSendChat, withUserInfo: userInfo)
                } else {
                    // We replied to the message, so we can assume, we read it as well
                    NCDatabaseManager.sharedInstance().decreaseUnreadBadgeNumber(forAccountId: pushNotification.accountId)
                    self.updateAppIconBadgeNumber()
                    if let room = NCDatabaseManager.sharedInstance().room(withToken: pushNotification.roomToken, forAccountId: pushNotification.accountId) {
                        NCIntentController.sharedInstance().donateSendMessageIntent(for: room)
                    }
                }

                application.endBackgroundTask(sendTask)
                sendTask = .invalid
            }
        }
    }

    private func handlePushNotificationResponseForFederation(_ serverNotification: NCNotification?, withActionIdentifier actionIdentifier: String, forAccount account: TalkAccount?) {
        guard let account, let serverNotification else {
            return
        }

        let bgTask = BGTaskHelper.startBackgroundTask(withName: "handlePushNotificationResponseForFederation") { _ in
            NCLog.log("ExpirationHandler called - handlePushNotificationResponseForFederation")
        }

        if actionIdentifier == NCNotificationController.actionFederationInvitationAccept {
            let invitation = FederationInvitation(notification: serverNotification, for: account.accountId)

            NCAPIController.sharedInstance().acceptFederationInvitation(for: account.accountId, with: invitation.invitationId) { success in
                if !success {
                    var userInfo: [AnyHashable: Any] = [:]
                    userInfo["roomToken"] = serverNotification.roomToken
                    userInfo["localNotificationType"] = NCLocalNotificationType.failedToAcceptInvitation.rawValue
                    userInfo["accountId"] = account.accountId

                    self.show(.failedToAcceptInvitation, withUserInfo: userInfo)
                }

                NCDatabaseManager.sharedInstance().decreasePendingFederationInvitation(forAccountId: account.accountId)

                bgTask.stopBackgroundTask()
            }
        } else if actionIdentifier == NCNotificationController.actionFederationInvitationReject {
            let invitation = FederationInvitation(notification: serverNotification, for: account.accountId)

            NCAPIController.sharedInstance().rejectFederationInvitation(for: account.accountId, with: invitation.invitationId) { _ in
                NCDatabaseManager.sharedInstance().decreasePendingFederationInvitation(forAccountId: account.accountId)
                bgTask.stopBackgroundTask()
            }
        } else {
            bgTask.stopBackgroundTask()

            let alert = UIAlertController(title: serverNotification.subject, message: serverNotification.message, preferredStyle: .alert)

            for notificationAction in serverNotification.notificationActions {
                let tempButton = UIAlertAction(title: notificationAction.actionLabel, style: .default) { _ in
                    NCDatabaseManager.sharedInstance().decreasePendingFederationInvitation(forAccountId: account.accountId)
                    NCAPIController.sharedInstance().executeNotificationAction(notificationAction, forAccount: account, completionBlock: nil)
                }

                alert.addAction(tempButton)
            }

            DispatchQueue.main.async {
                NCUserInterfaceController.sharedInstance().presentAlertViewController(alert)
            }
        }
    }

    private func handlePushNotificationResponseForRecording(_ serverNotification: NCNotification?, withActionIdentifier actionIdentifier: String, forAccount account: TalkAccount?) {
        guard let account, let serverNotification else {
            return
        }

        let bgTask = BGTaskHelper.startBackgroundTask(withName: "handlePushNotificationResponseForRecording") { _ in
            NCLog.log("ExpirationHandler called - handlePushNotificationResponseForRecording")
        }

        let notificationTimeInterval = serverNotification.datetime?.timeIntervalSince1970 ?? 0
        let notificationTimestamp = String(format: "%.0f", notificationTimeInterval)

        if actionIdentifier == NCNotificationController.actionShareRecording {
            let fileParameters = serverNotification.messageRichParameters["file"] as? [AnyHashable: Any]

            guard let fileParameters, let fileId = fileParameters["id"] as? String else {
                bgTask.stopBackgroundTask()
                return
            }

            NCAPIController.sharedInstance().shareStoredRecording(withTimestamp: notificationTimestamp, withFileId: fileId, forRoom: serverNotification.roomToken, forAccount: account) { error in
                if error != nil {
                    var userInfo: [AnyHashable: Any] = [:]
                    userInfo["roomToken"] = serverNotification.roomToken
                    userInfo["localNotificationType"] = NCLocalNotificationType.failedToShareRecording.rawValue
                    userInfo["accountId"] = account.accountId

                    self.show(.failedToShareRecording, withUserInfo: userInfo)
                }

                bgTask.stopBackgroundTask()
            }
        } else if actionIdentifier == NCNotificationController.actionDismissRecordingNotification {
            NCAPIController.sharedInstance().dismissStoredRecordingNotification(withTimestamp: notificationTimestamp, forRoom: serverNotification.roomToken, forAccount: account) { _ in
                bgTask.stopBackgroundTask()
            }
        } else {
            bgTask.stopBackgroundTask()

            let alert = UIAlertController(title: serverNotification.subject, message: serverNotification.message, preferredStyle: .alert)

            let notificationActions = serverNotification.notificationActions
            for notificationAction in notificationActions {
                let tempButton = UIAlertAction(title: notificationAction.actionLabel, style: .default) { _ in
                    NCAPIController.sharedInstance().executeNotificationAction(notificationAction, forAccount: account, completionBlock: nil)
                }

                alert.addAction(tempButton)
            }

            if notificationActions.isEmpty {
                // Make sure that we have at least a way to dismiss the notification, if there are no actions
                let okButton = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil)
                alert.addAction(okButton)
            }

            DispatchQueue.main.async {
                NCUserInterfaceController.sharedInstance().presentAlertViewController(alert)
            }
        }
    }

    private func handlePushNotificationResponseForReminder(_ serverNotification: NCNotification?, withActionIdentifier actionIdentifier: String, forAccount account: TalkAccount?) {
        guard let account, let serverNotification else {
            return
        }

        if NCRoomsManager.shared.callViewController != nil {
            return
        }

        let bgTask = BGTaskHelper.startBackgroundTask(withName: "handlePushNotificationResponseForReminder") { _ in
            NCLog.log("ExpirationHandler called - handlePushNotificationResponseForReminder")
        }

        // Open the conversation for the reminder
        NCRoomsManager.shared.startChat(withRoomToken: serverNotification.roomToken)

        // After opening the notification, we need to execute the DELETE action
        for dict in serverNotification.actions {
            let notificationAction = NCNotificationAction(dictionary: dict)

            if notificationAction.actionType == .kNotificationActionTypeDelete {
                NCAPIController.sharedInstance().executeNotificationAction(notificationAction, forAccount: account) { _ in
                    bgTask.stopBackgroundTask()
                }

                break
            }
        }
    }

    private func handlePushNotificationResponse(_ pushNotification: NCPushNotification) {
        if NCRoomsManager.shared.callViewController != nil {
            return
        }

        switch pushNotification.type {
        case .call:
            NCUserInterfaceController.sharedInstance().presentAlert(for: pushNotification)
        case .room, .chat:
            NCUserInterfaceController.sharedInstance().presentChat(for: pushNotification)
        default:
            break
        }
    }

    private func handleLocalNotificationResponse(_ notificationUserInfo: [AnyHashable: Any]) {
        if NCRoomsManager.shared.callViewController != nil {
            return
        }

        let localNotificationType = NCLocalNotificationType(rawValue: (notificationUserInfo["localNotificationType"] as? NSNumber)?.intValue ?? 0)
        guard let localNotificationType, localNotificationType.rawValue > 0 else {
            return
        }

        switch localNotificationType {
        case .missedCall, .cancelledCall, .failedSendChat, .chatNotification, .recordingConsentRequired:
            NCUserInterfaceController.sharedInstance().presentChat(forLocalNotification: notificationUserInfo)
        case .callFromOldAccount:
            NCUserInterfaceController.sharedInstance().presentSettingsViewController()
        default:
            break
        }
    }
}
