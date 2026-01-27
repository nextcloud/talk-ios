//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitNCNotificationTest: XCTestCase {

    func testCallNotification() throws {
        let notificationJsonData = """
          {
            "notification_id": 1425,
            "app": "spreed",
            "user": "admin",
            "datetime": "2026-01-17T23:58:35+00:00",
            "object_type": "call",
            "object_id": "5tsemb7k",
            "subject": "Du hast einen Gruppenanruf in Test verpasst",
            "message": "",
            "link": "https://nextcloud.internal/index.php/call/5tsemb7k",
            "subjectRich": "Du hast einen Gruppenanruf in {call} verpasst",
            "subjectRichParameters": {
              "call": {
                "type": "call",
                "id": "127",
                "name": "Test",
                "call-type": "group",
                "icon-url": "https://nextcloud.internal/ocs/v2.php/apps/spreed/api/v1/room/5tsemb7k/avatar?v=02234d2d"
              }
            },
            "messageRich": "",
            "messageRichParameters": [],
            "icon": "https://nextcloud.internal/apps-extra/spreed/img/app-dark.svg",
            "shouldNotify": true,
            "actions": [
              {
                "label": "Chat anzeigen",
                "link": "https://nextcloud.internal/index.php/call/5tsemb7k",
                "type": "WEB",
                "primary": false
              }
            ]
          }
        """

        // swiftlint:disable:next force_cast
        let dataDict = try JSONSerialization.jsonObject(with: notificationJsonData.data(using: .utf8)!) as! [String: Any]
        let notification = NCNotification(dictionary: dataDict)

        XCTAssertEqual(notification?.notificationId, 1425)
        XCTAssertEqual(notification?.objectId, "5tsemb7k")
        XCTAssertEqual(notification?.objectType, "call")
        XCTAssertEqual(notification?.app, "spreed")
        XCTAssertEqual(notification?.subject, "Du hast einen Gruppenanruf in Test verpasst")
        XCTAssertEqual(notification?.roomToken, "5tsemb7k")
        XCTAssertEqual(notification?.notificationType, .call)
        XCTAssertEqual(notification?.datetime, Date(timeIntervalSince1970: 1768694315))

        let firstAction = notification?.notificationActions.first
        XCTAssertEqual(firstAction?.actionLabel, "Chat anzeigen")
        XCTAssertEqual(firstAction?.actionType, .kNotificationActionTypeWeb)
        XCTAssertEqual(firstAction?.actionLink, "https://nextcloud.internal/index.php/call/5tsemb7k")
        XCTAssertEqual(firstAction?.isPrimaryAction, false)
    }

    func testChatNotification() throws {
        let notificationJsonData = """
          {
            "notification_id": 1422,
            "app": "spreed",
            "user": "admin",
            "datetime": "2026-01-17T23:58:22+00:00",
            "object_type": "chat",
            "object_id": "5tsemb7k/3013",
            "subject": "bob ABC 1234 Test hat eine Nachricht in der Unterhaltung Test gesendet",
            "message": "Test",
            "link": "https://nextcloud.internal/index.php/call/5tsemb7k#message_3013",
            "subjectRich": "{user} hat eine Nachricht in der Unterhaltung {call} gesendet",
            "subjectRichParameters": {
              "user": {
                "type": "user",
                "id": "bob",
                "name": "bob ABC 1234 Test"
              },
              "call": {
                "type": "call",
                "id": "127",
                "name": "Test",
                "call-type": "group",
                "icon-url": "https://nextcloud.internal/ocs/v2.php/apps/spreed/api/v1/room/5tsemb7k/avatar?v=02234d2d"
              }
            },
            "messageRich": "Test",
            "messageRichParameters": [],
            "icon": "https://nextcloud.internal/apps-extra/spreed/img/app-dark.svg",
            "shouldNotify": true,
            "actions": [
              {
                "label": "Chat anzeigen",
                "link": "https://nextcloud.internal/index.php/call/5tsemb7k#message_3013",
                "type": "WEB",
                "primary": false
              }
            ]
          }
        """

        // swiftlint:disable:next force_cast
        let dataDict = try JSONSerialization.jsonObject(with: notificationJsonData.data(using: .utf8)!) as! [String: Any]
        let notification = NCNotification(dictionary: dataDict)

        XCTAssertEqual(notification?.notificationId, 1422)
        XCTAssertEqual(notification?.objectId, "5tsemb7k/3013")
        XCTAssertEqual(notification?.objectType, "chat")
        XCTAssertEqual(notification?.app, "spreed")
        XCTAssertEqual(notification?.subject, "bob ABC 1234 Test hat eine Nachricht in der Unterhaltung Test gesendet")
        XCTAssertEqual(notification?.chatMessageTitle, "bob ABC 1234 Test in Test")
        XCTAssertEqual(notification?.roomToken, "5tsemb7k")
        XCTAssertEqual(notification?.notificationType, .chat)
        XCTAssertEqual(notification?.datetime, Date(timeIntervalSince1970: 1768694302))
    }

    func testThreadNotification() throws {
        let notificationJsonData = """
        {
          "notification_id": 1431,
          "app": "spreed",
          "user": "admin",
          "datetime": "2026-01-18T00:26:12+00:00",
          "object_type": "chat",
          "object_id": "5tsemb7k/3019/3017",
          "subject": "bob ABC 1234 Test hat eine Nachricht in der Unterhaltung Test gesendet",
          "message": "Hello",
          "link": "https://nextcloud.internal/index.php/call/5tsemb7k?threadId=3017#message_3019",
          "subjectRich": "{user} hat eine Nachricht in der Unterhaltung {call} gesendet",
          "subjectRichParameters": {
            "user": {
              "type": "user",
              "id": "bob",
              "name": "bob ABC 1234 Test"
            },
            "call": {
              "type": "call",
              "id": "127",
              "name": "Test",
              "call-type": "group",
              "icon-url": "https://nextcloud.internal/ocs/v2.php/apps/spreed/api/v1/room/5tsemb7k/avatar?v=02234d2d"
            }
          },
          "messageRich": "Hello",
          "messageRichParameters": [],
          "icon": "https://nextcloud.internal/apps-extra/spreed/img/app-dark.svg",
          "shouldNotify": true,
          "actions": [
            {
              "label": "Chat anzeigen",
              "link": "https://nextcloud.internal/index.php/call/5tsemb7k?threadId=3017#message_3019",
              "type": "WEB",
              "primary": false
            }
          ]
        }
    """

        // swiftlint:disable:next force_cast
        let dataDict = try JSONSerialization.jsonObject(with: notificationJsonData.data(using: .utf8)!) as! [String: Any]
        let notification = NCNotification(dictionary: dataDict)

        XCTAssertEqual(notification?.notificationId, 1431)
        XCTAssertEqual(notification?.objectId, "5tsemb7k/3019/3017")
        XCTAssertEqual(notification?.objectType, "chat")
        XCTAssertEqual(notification?.app, "spreed")
        XCTAssertEqual(notification?.subject, "bob ABC 1234 Test hat eine Nachricht in der Unterhaltung Test gesendet")
        XCTAssertEqual(notification?.chatMessageTitle, "bob ABC 1234 Test in Test")
        XCTAssertEqual(notification?.roomToken, "5tsemb7k")
        XCTAssertEqual(notification?.threadId, 3017)
        XCTAssertEqual(notification?.notificationType, .chat)
        XCTAssertEqual(notification?.datetime, Date(timeIntervalSince1970: 1768695972))
    }

}
