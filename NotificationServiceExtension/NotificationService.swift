//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import UserNotifications
import SDWebImage

class NotificationService: UNNotificationServiceExtension {

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?
    private var sendMessageIntent: INSendMessageIntent?

    // swiftlint:disable:next cyclomatic_complexity
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        self.bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent

        self.bestAttemptContent?.title = ""
        self.bestAttemptContent?.body = NSLocalizedString("You received a new notification", comment: "")

        // Configure database
        guard let containerBase = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            self.showBestAttemptNotification()
            return
        }

        let databaseUrl = containerBase.appending(path: kTalkDatabaseFolder, directoryHint: .isDirectory).appending(path: kTalkDatabaseFileName, directoryHint: .notDirectory)

        guard !FileManager.default.fileExists(atPath: databaseUrl.path()) else {
            print("Database does not exist -> main app needs to run before extension")

            self.showBestAttemptNotification()
            return
        }

        var currentSchemaVersion: UInt64 = 0

        // schemaVersionAtURL throws an exception when file is not readable
        do {
            currentSchemaVersion = try RLMRealm.schemaVersion(at: databaseUrl)
        } catch {
            print("Reading schemaVersion failed: \(error.localizedDescription)")

            self.showBestAttemptNotification()
            return
        }

        if currentSchemaVersion != kTalkDatabaseSchemaVersion {
            print("Current schemaVersion is \(currentSchemaVersion), app schemaVersion is \(kTalkDatabaseSchemaVersion)")
            print("Database needs migration -> don't open database from extension")

            self.showBestAttemptNotification()
            return
        }

        let configuration = RLMRealmConfiguration.default()
        configuration.fileURL = databaseUrl
        configuration.schemaVersion = kTalkDatabaseSchemaVersion
        configuration.objectClasses = [TalkAccount.self, NCRoom.self, ServerCapabilities.self, FederatedCapabilities.self]
        RLMRealmConfiguration.setDefault(configuration)

        // We don't want to use a memory cache in NSE, because we only have a total of 24MB before we get killed by the OS
        SDImageCache.shared.config.shouldCacheImagesInMemory = false

        let message = self.bestAttemptContent?.userInfo["subject"] as? String
        let signature = self.bestAttemptContent?.userInfo["signature"] as? String

        guard let message, let signature else {
            // Without a message or signature there's nothing left to do here
            self.showBestAttemptNotification()
            return
        }

        var pushNotification: NCPushNotification?
        var account: TalkAccount?

        for case let talkAccount as TalkAccount in TalkAccount.allObjects() {
            let decryptedMessage = NCPushNotificationsUtils.decryptPushNotification(withMessageBase64: message, withSignatureBase64: signature, forAccount: talkAccount)

            if let decryptedMessage {
                pushNotification = NCPushNotification(fromDecryptedString: decryptedMessage, withAccountId: talkAccount.accountId)
                account = TalkAccount(value: talkAccount)

                break
            }
        }

        guard let pushNotification, let account else {
            // At this point we tried everything to decrypt the received message
            // No need to wait for the extension timeout, nothing is happening anymore

            self.showBestAttemptNotification()
            return
        }

        if pushNotification.type == .NCPushNotificationTypeAdminNotification {
            // Test notification send through "occ notification:test-push --talk <userid>"
            // No need to increase the badge or query the server about it

            self.bestAttemptContent?.body = pushNotification.subject
            self.showBestAttemptNotification()
            return
        }

        // TODO: Can we just use the managed object we already had before?
        try? RLMRealm.default().transaction {
            let query = NSPredicate(format: "accountId = %@", account.accountId)

            // Update unread notifications counter for push notification account
            if let managedAccount = TalkAccount.objects(with: query).firstObject() as? TalkAccount {
                managedAccount.unreadBadgeNumber += 1
                managedAccount.unreadNotification = (managedAccount.active) ? false : true
            }
        }

        // Get the total number of unread notifications
        var unreadNotifications = 0
        for case let talkAccount as TalkAccount in TalkAccount.allObjects() {
            unreadNotifications += talkAccount.unreadBadgeNumber
        }

        self.bestAttemptContent?.body = pushNotification.bodyForRemoteAlerts()
        self.bestAttemptContent?.threadIdentifier = pushNotification.roomToken
        self.bestAttemptContent?.sound = .default
        self.bestAttemptContent?.badge = unreadNotifications as NSNumber

        if pushNotification.type == .NCPushNotificationTypeChat {
            // Set category for chat messages to allow interactive notifications
            self.bestAttemptContent?.categoryIdentifier = "CATEGORY_CHAT"
        }

        var userInfo: [String: Any] = [
            "pushNotification": pushNotification.jsonString,
            "accountId": pushNotification.accountId,
            "notificationId": pushNotification.notificationId
        ]

        self.bestAttemptContent?.userInfo = userInfo

        // Create title and body structure if there is a new line in the subject
        let components = pushNotification.subject.split(whereSeparator: \.isNewline)
        if components.count > 1 {
            self.bestAttemptContent?.title = String(components[0])
            self.bestAttemptContent?.body = components.dropFirst().joined(separator: "\n")
        }

        NCAPIController.shared.getServerNotification(withId: pushNotification.notificationId, forAccount: account) { serverNotification, dataDict, error in
            guard let serverNotification, let dataDict, error == nil else {
                // Even if the server request fails, we should try to create a conversation notifications
                self.createAndShowConversationNotification(withPushNotification: pushNotification)
                return
            }

            // Add the serverNotification as userInfo as well -> this can later be used to access the actions directly
            userInfo["serverNotification"] = dataDict
            self.bestAttemptContent?.userInfo = userInfo

            if serverNotification.notificationType == .chat {
                self.handleChatNotification(withServerNotification: serverNotification, withPushNotification: pushNotification, forAccount: account)
            } else if serverNotification.notificationType == .recording {
                self.handleRecordingNotification(withServerNotification: serverNotification, withPushNotification: pushNotification, forAccount: account)
            } else if serverNotification.notificationType == .federation {
                self.handleFederationNotification(withServerNotification: serverNotification, withPushNotification: pushNotification, forAccount: account)
            }
        }
    }

    private func handleChatNotification(withServerNotification serverNotification: NCNotification, withPushNotification pushNotification: NCPushNotification, forAccount account: TalkAccount) {
        // Only try to adjust the title/body if there are rich parameters
        // E.g. for sensitive conversations, there are none, so we use the server provided title/body
        if !serverNotification.subjectRichParameters.isEmpty {
            let attributedMessage = NSAttributedString(string: serverNotification.message)
            let markdownMessage = SwiftMarkdownObjCBridge.parseMarkdown(markdownString: attributedMessage)

            self.bestAttemptContent?.title = serverNotification.chatMessageTitle
            self.bestAttemptContent?.body = markdownMessage.string
        }

        guard let fileDict = serverNotification.messageRichParameters["file"] as? [String: Any], fileDict[boolForKey: "preview-available"] ?? false else {
            // No file/no preview -> show notification
            self.createAndShowConversationNotification(withPushNotification: pushNotification)
            return
        }

        // First try to create the conversation notification, and only afterwards try to retrieve the image preview
        self.createConversationNotification(withPushNotification: pushNotification) {
            guard let fileId = fileDict[stringForKey: "id"] else {
                self.showBestAttemptNotification()
                return
            }

            SDWebImageDownloader.shared.config.downloadTimeout = 25.0
            NCAPIController.shared.getPreviewForFile(fileId, width: 0, height: 512, forAccount: account) { image, _ in
                if let image, let attachment = self.getNotificationAttachment(fromImage: image, forAccountId: account.accountId) {
                    self.bestAttemptContent?.attachments = [attachment]
                }

                self.showBestAttemptNotification()
            }
        }
    }

    private func handleRecordingNotification(withServerNotification serverNotification: NCNotification, withPushNotification pushNotification: NCPushNotification, forAccount account: TalkAccount) {
        self.bestAttemptContent?.categoryIdentifier = "CATEGORY_RECORDING"
        self.bestAttemptContent?.title = serverNotification.subject
        self.bestAttemptContent?.body = serverNotification.message

        self.createAndShowConversationNotification(withPushNotification: pushNotification)
    }

    private func handleFederationNotification(withServerNotification serverNotification: NCNotification, withPushNotification pushNotification: NCPushNotification, forAccount account: TalkAccount) {
        self.bestAttemptContent?.categoryIdentifier = "CATEGORY_FEDERATION"
        self.bestAttemptContent?.title = serverNotification.subject
        self.bestAttemptContent?.body = serverNotification.message

        NCDatabaseManager.sharedInstance().increasePendingFederationInvitation(forAccountId: account.accountId)
        self.createAndShowConversationNotification(withPushNotification: pushNotification)
    }

    private func createConversationNotification(withPushNotification pushNotification: NCPushNotification, withCompletionBlock completionBlock: @escaping () -> Void) {
        if let bestAttemptContent = self.bestAttemptContent, let room = NCDatabaseManager.sharedInstance().room(withToken: pushNotification.roomToken, forAccountId: pushNotification.accountId) {
            NCIntentController.sharedInstance().getInteractionFor(room, withTitle: bestAttemptContent.title) { sendMessageIntent in
                self.sendMessageIntent = sendMessageIntent
                completionBlock()
            }
        } else {
            completionBlock()
        }
    }

    private func createAndShowConversationNotification(withPushNotification pushNotification: NCPushNotification) {
        self.createConversationNotification(withPushNotification: pushNotification) {
            self.showBestAttemptNotification()
        }
    }

    private func showBestAttemptNotification() {
        guard let bestAttemptContent = self.bestAttemptContent else { return }

        // When we have a send message intent, we use it, otherwise we fall back to the non-conversation-notification one
        if let sendMessageIntent = self.sendMessageIntent, let updatedContent = try? bestAttemptContent.updating(from: sendMessageIntent) {
            self.contentHandler?(updatedContent)
        } else {
            self.contentHandler?(bestAttemptContent)
        }
    }

    private func getNotificationAttachment(fromImage image: UIImage, forAccountId accountId: String) -> UNNotificationAttachment? {
        guard let encodedAccountId = accountId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return nil }

        let tempDirectoryPath = FileManager.default.temporaryDirectory.appending(path: "/download/").appending(path: encodedAccountId)

        // Make sure our download directory exists
        try? FileManager.default.createDirectory(at: tempDirectoryPath, withIntermediateDirectories: true)

        let fileName = "NotificationPreview_\(UUID().uuidString).jpg"
        let fileUrl = tempDirectoryPath.appending(path: fileName)

        // Write the received image to the temporary directory and create the corresponding attachment object
        if (try? image.jpegData(compressionQuality: 1.0)?.write(to: fileUrl, options: .atomic)) != nil {
            if let attachment = try? UNNotificationAttachment(identifier: fileName, url: fileUrl) {
                return attachment
            }
        }

        return nil
    }

    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        self.showBestAttemptNotification()
    }

}
