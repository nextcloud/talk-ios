//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

extension Notification.Name {
    static let NCChatViewControllerReplyPrivatelyNotification = Notification.Name(rawValue: "NCChatViewControllerReplyPrivatelyNotification")
    static let NCChatViewControllerForwardNotification = Notification.Name(rawValue: "NCChatViewControllerForwardNotification")
    static let NCChatViewControllerTalkToUserNotification = Notification.Name(rawValue: "NCChatViewControllerTalkToUserNotification")
}

@objc extension NSNotification {
    public static let NCChatViewControllerReplyPrivatelyNotification = Notification.Name.NCChatViewControllerReplyPrivatelyNotification
    public static let NCChatViewControllerForwardNotification = Notification.Name.NCChatViewControllerForwardNotification
    public static let NCChatViewControllerTalkToUserNotification = Notification.Name.NCChatViewControllerTalkToUserNotification
}
