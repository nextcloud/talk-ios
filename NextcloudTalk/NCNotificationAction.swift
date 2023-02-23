//
// Copyright (c) 2023 Marcel Müller <marcel.mueller@nextcloud.com>
//
// Author Marcel Müller <marcel.mueller@nextcloud.com>
//
// GNU GPL version 3 or any later version
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
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
