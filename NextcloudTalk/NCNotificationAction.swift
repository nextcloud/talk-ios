//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

// Documentation at https://github.com/nextcloud/notifications/blob/master/docs/ocs-endpoint-v2.md
// Type "Web" is supposed to do a redirect
@objc enum NCNotificationActionType: Int {
    case kNotificationActionTypeUnknown = 0
    case kNotificationActionTypeGet
    case kNotificationActionTypePost
    case kNotificationActionTypeDelete
    case kNotificationActionTypePut
    case kNotificationActionTypeWeb
}

@objcMembers class NCNotificationAction: NSObject {

    public let actionLabel: String?
    public var actionLink: String?
    public var actionType: NCNotificationActionType = .kNotificationActionTypeUnknown
    public var isPrimaryAction: Bool

    init(dictionary: [String: Any]) {
        self.actionLabel = dictionary["label"] as? String
        self.actionLink = dictionary["link"] as? String
        self.isPrimaryAction = dictionary["primary"] as? Bool ?? false

        if let actionType = dictionary["type"] as? String {
            switch actionType.lowercased() {
            case "get":
                self.actionType = .kNotificationActionTypeGet
            case "post":
                self.actionType = .kNotificationActionTypePost
            case "delete":
                self.actionType = .kNotificationActionTypeDelete
            case "put":
                self.actionType = .kNotificationActionTypePut
            case "web":
                self.actionType = .kNotificationActionTypeWeb
            default:
                self.actionType = .kNotificationActionTypeUnknown
            }
        }

        super.init()
    }
}
