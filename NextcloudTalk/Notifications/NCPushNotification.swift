//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

public extension Notification.Name {
    static let NCPushNotificationJoinChat = Notification.Name(rawValue: "NCPushNotificationJoinChatNotification")
    static let NCPushNotificationJoinAudioCallAccepted = Notification.Name(rawValue: "NCPushNotificationJoinAudioCallAcceptedNotification")
    static let NCPushNotificationJoinVideoCallAccepted = Notification.Name(rawValue: "NCPushNotificationJoinVideoCallAcceptedNotification")
}

enum NCPushNotificationType: Int {
    case unknown
    case call
    case room
    case chat
    case delete
    case deleteAll
    case deleteMultiple
    case adminNotification
    case recording
    case federation
    case reminder
}

public class NCPushNotification {

    private static let talkAppId = "spreed"
    private static let adminNotificationAppId = "admin_notification_talk"

    var app = ""
    var type: NCPushNotificationType = .unknown
    var subject = ""
    var roomToken = ""
    var threadId = 0
    var notificationId = 0
    var notificationIds: [NSNumber]?
    var accountId: String
    var jsonString = ""
    var responseUserText = ""

    init?(fromDecryptedString decryptedString: String, withAccountId accountId: String?) {
        guard let data = decryptedString.data(using: .utf8),
              let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        self.accountId = accountId ?? ""

        let app = jsonDict["app"] as? String
        guard app == NCPushNotification.talkAppId else {
            guard self.parseNonTalkPushNotification(jsonDict) else { return nil }
            return
        }

        self.app = NCPushNotification.talkAppId
        self.subject = jsonDict["subject"] as? String ?? ""
        self.roomToken = jsonDict["id"] as? String ?? ""
        self.notificationId = NCPushNotification.intValue(jsonDict["nid"])
        self.jsonString = decryptedString

        switch jsonDict["type"] as? String {
        case "call":
            self.type = .call
        case "room":
            self.type = .room
        case "chat":
            self.type = .chat
        case "recording":
            self.type = .recording
        case "remote_talk_share":
            self.type = .federation
        case "reminder":
            self.type = .reminder
        default:
            self.type = .unknown
        }
    }

    private func parseNonTalkPushNotification(_ jsonDict: [String: Any]) -> Bool {
        if jsonDict["delete"] != nil {
            self.notificationId = NCPushNotification.intValue(jsonDict["nid"])
            self.type = .delete
        } else if jsonDict["delete-all"] != nil {
            self.type = .deleteAll
        } else if jsonDict["delete-multiple"] != nil {
            self.notificationIds = jsonDict["nids"] as? [NSNumber]
            self.type = .deleteMultiple
        } else if jsonDict["app"] as? String == NCPushNotification.adminNotificationAppId {
            self.subject = jsonDict["subject"] as? String ?? ""
            self.notificationId = NCPushNotification.intValue(jsonDict["nid"])
            self.type = .adminNotification
        } else {
            return false
        }

        return true
    }

    func bodyForRemoteAlerts() -> String {
        switch type {
        case .call:
            return "📞 \(subject)"
        case .room:
            return "🔔 \(subject)"
        case .chat:
            return "💬 \(subject)"
        default:
            return subject
        }
    }

    private static func intValue(_ value: Any?) -> Int {
        if let number = value as? NSNumber {
            return number.intValue
        }

        return (value as? String).flatMap { Int($0) } ?? 0
    }
}
