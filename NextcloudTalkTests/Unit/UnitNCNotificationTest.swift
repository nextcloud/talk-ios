//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Testing
@testable import NextcloudTalk

struct UnitNCNotificationTest {

    @Test func `call notification`() throws {
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

        let dataDict = try JSONSerialization.jsonObject(with: notificationJsonData.data(using: .utf8)!) as! [String: Any]
        let notification = NCNotification(dictionary: dataDict)

        #expect(notification?.notificationId == 1425)
        #expect(notification?.objectId == "5tsemb7k")
        #expect(notification?.objectType == "call")
        #expect(notification?.app == "spreed")
        #expect(notification?.subject == "Du hast einen Gruppenanruf in Test verpasst")
        #expect(notification?.roomToken == "5tsemb7k")
        #expect(notification?.notificationType == .call)
        #expect(notification?.datetime == Date(timeIntervalSince1970: 1768694315))

        let firstAction = notification?.notificationActions.first
        #expect(firstAction?.actionLabel == "Chat anzeigen")
        #expect(firstAction?.actionType == .kNotificationActionTypeWeb)
        #expect(firstAction?.actionLink == "https://nextcloud.internal/index.php/call/5tsemb7k")
        #expect(firstAction?.isPrimaryAction == false)
    }

    @Test func `chat notification`() throws {
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

        let dataDict = try JSONSerialization.jsonObject(with: notificationJsonData.data(using: .utf8)!) as! [String: Any]
        let notification = NCNotification(dictionary: dataDict)

        #expect(notification?.notificationId == 1422)
        #expect(notification?.objectId == "5tsemb7k/3013")
        #expect(notification?.objectType == "chat")
        #expect(notification?.app == "spreed")
        #expect(notification?.subject == "bob ABC 1234 Test hat eine Nachricht in der Unterhaltung Test gesendet")
        #expect(notification?.chatMessageTitle == "bob ABC 1234 Test in Test")
        #expect(notification?.roomToken == "5tsemb7k")
        #expect(notification?.notificationType == .chat)
        #expect(notification?.datetime == Date(timeIntervalSince1970: 1768694302))
    }

    @Test func `thread notification`() throws {
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

        let dataDict = try JSONSerialization.jsonObject(with: notificationJsonData.data(using: .utf8)!) as! [String: Any]
        let notification = NCNotification(dictionary: dataDict)

        #expect(notification?.notificationId == 1431)
        #expect(notification?.objectId == "5tsemb7k/3019/3017")
        #expect(notification?.objectType == "chat")
        #expect(notification?.app == "spreed")
        #expect(notification?.subject == "bob ABC 1234 Test hat eine Nachricht in der Unterhaltung Test gesendet")
        #expect(notification?.chatMessageTitle == "bob ABC 1234 Test in Test")
        #expect(notification?.roomToken == "5tsemb7k")
        #expect(notification?.threadId == 3017)
        #expect(notification?.notificationType == .chat)
        #expect(notification?.datetime == Date(timeIntervalSince1970: 1768695972))
    }

}
