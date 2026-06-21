//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Testing
@testable import NextcloudTalk

@Suite(.serialized)
final class IntegrationNCNotificationControllerTest: TestBase {

    @Test func `notifications self test`() async throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        if !NCDatabaseManager.sharedInstance().serverHasNotificationsCapability(kNotificationsCapabilityTestPush, forAccountId: activeAccount.accountId) {
            try Test.cancel("Missing 'test-push' capability of notifications app")
        }

        let returnsNotificationIdOnTestPush = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId)!.versionMajor >= 32

        // Create a self-test notification
        let (message, optionalNotificationId) = try await NCAPIController.sharedInstance().testPushnotifications(forAccount: activeAccount)
        #expect(!message.isEmpty)

        if !returnsNotificationIdOnTestPush {
            return
        }

        let notificationId = try #require(optionalNotificationId, "Did not receive notificationId, but expected it")

        // Try to retrieve the created notification
        await withCheckedContinuation { continuation in
            NCAPIController.sharedInstance().getServerNotification(withId: notificationId, forAccount: activeAccount) { notification, _, error in
                #expect(notification?.notificationId == notificationId)

                // Check the existance of the notification
                NCAPIController.sharedInstance().checkNotificationExistance(withIds: [notificationId], forAccount: activeAccount) { notification, error in
                    #expect(notification?.first(where: { $0 == notificationId }) != nil)
                    #expect(error == nil)

                    continuation.resume()
                }
            }
        }

        // Use our own delegate, as we would otherwise immediately remove the notification in NCNotificationController
        let notificationCenterDelegate = UNNotificationCenterDelegateMock()
        UNUserNotificationCenter.current().delegate = notificationCenterDelegate

        // Try to create a local notification, mimicking the created notification
        let content = UNMutableNotificationContent()
        content.title = "Test notification"
        content.userInfo = [
            "accountId": activeAccount.accountId,
            "notificationId": notificationId
        ]

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try await UNUserNotificationCenter.current().add(request)

        // Check that the notification was correctly delivered
        var deliveredNotifications = await UNUserNotificationCenter.current().deliveredNotifications()
        #expect(deliveredNotifications.contains(where: { $0.request.content.userInfo[intForKey: "notificationId"] == notificationId }))

        // Remove the notification from the server
        try await NCAPIController.sharedInstance().deleteServerNotification(withId: notificationId, forAccount: activeAccount)

        // Check if we remove the notification correctly (e.g. in a background-fetch)
        try await NCNotificationController.sharedInstance().checkNotificationExistance()
        deliveredNotifications = await UNUserNotificationCenter.current().deliveredNotifications()
        #expect(deliveredNotifications.isEmpty)
    }

}
