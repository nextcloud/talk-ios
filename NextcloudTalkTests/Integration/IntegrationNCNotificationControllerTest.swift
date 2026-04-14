//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
import Foundation
@testable import NextcloudTalk

final class IntegrationNCNotificationControllerTest: TestBase {

    func testNotificationsSelfTest() async throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        if !NCDatabaseManager.sharedInstance().serverHasNotificationsCapability(kNotificationsCapabilityTestPush, forAccountId: activeAccount.accountId) {
            throw XCTSkip("Missing 'test-push' capability of notifications app")
        }

        let returnsNotificationIdOnTestPush = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId)!.versionMajor >= 32

        // Create a self-test notification
        let (message, notificationId) = try await NCAPIController.sharedInstance().testPushnotifications(forAccount: activeAccount)
        XCTAssertNotEqual(message, "")

        if !returnsNotificationIdOnTestPush {
            return
        }

        guard returnsNotificationIdOnTestPush, let notificationId else {
            XCTFail("Did not receive notificationId, but expected it")
            return
        }

        // Try to retrieve the created notification
        let exp = expectation(description: "\(#function)\(#line)")
        NCAPIController.sharedInstance().getServerNotification(withId: notificationId, forAccount: activeAccount) { notification, error in
            XCTAssertEqual(notification?.notificationId, notificationId)

            // Check the existance of the notification
            NCAPIController.sharedInstance().checkNotificationExistance(withIds: [notificationId], forAccount: activeAccount) { notification, error in
                XCTAssertNotNil((notification?.first(where: { $0 == notificationId })))
                XCTAssertNil(error)

                exp.fulfill()
            }
        }

        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)

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
        XCTAssertTrue(deliveredNotifications.contains(where: { $0.request.content.userInfo[intForKey: "notificationId"] == notificationId }))

        // Remove the notification from the server
        try await NCAPIController.sharedInstance().deleteServerNotification(withId: notificationId, forAccount: activeAccount)

        // Check if we remove the notification correctly (e.g. in a background-fetch)
        try await NCNotificationController.sharedInstance().checkNotificationExistance()
        deliveredNotifications = await UNUserNotificationCenter.current().deliveredNotifications()
        XCTAssertEqual(deliveredNotifications.count, 0)
    }

}
