//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

let kUserStatusOnline = "online"
let kUserStatusAway = "away"
let kUserStatusBusy = "busy"
let kUserStatusDND = "dnd"
let kUserStatusInvisible = "invisible"
let kUserStatusOffline = "offline"

@objcMembers class NCUserStatus: NSObject {

    var userId = ""
    var status = ""
    var statusIsUserDefined = false
    var message = ""
    var messageId = ""
    var messageIsPredefined = false
    var icon = ""
    var clearAt = 0

    override init() {
        super.init()
    }

    init?(dictionary: [String: Any]?) {
        guard let dictionary else { return nil }

        self.userId = dictionary["userId"] as? String ?? ""
        self.status = dictionary["status"] as? String ?? ""
        self.statusIsUserDefined = dictionary["statusIsUserDefined"] as? Bool ?? false
        self.message = dictionary["message"] as? String ?? ""
        self.messageId = dictionary["messageId"] as? String ?? ""
        self.messageIsPredefined = dictionary["messageIsPredefined"] as? Bool ?? false
        self.icon = dictionary["icon"] as? String ?? ""
        self.clearAt = dictionary["clearAt"] as? Int ?? 0

        super.init()
    }

    static func readableUserStatus(fromUserStatus userStatus: String) -> String {
        switch userStatus {
        case kUserStatusOnline:
            return NSLocalizedString("Online", comment: "")
        case kUserStatusAway:
            return NSLocalizedString("Away", comment: "")
        case kUserStatusBusy:
            return NSLocalizedString("Busy", comment: "")
        case kUserStatusDND:
            return NSLocalizedString("Do not disturb", comment: "")
        case kUserStatusInvisible:
            return NSLocalizedString("Invisible", comment: "")
        case kUserStatusOffline:
            return NSLocalizedString("Offline", comment: "")
        default:
            return ""
        }
    }

    static func getOnlineSFIcon() -> UIImage {
        return UIImage(systemName: "checkmark.circle.fill")!.withTintColor(.systemGreen, renderingMode: .alwaysOriginal)
    }

    static func getAwaySFIcon() -> UIImage {
        return UIImage(systemName: "clock.fill")!.withTintColor(.systemYellow, renderingMode: .alwaysOriginal)
    }

    static func getBusySFIcon() -> UIImage {
        return UIImage(systemName: "circle.fill")!.withTintColor(.systemRed, renderingMode: .alwaysOriginal)
    }

    static func getDoNotDisturbSFIcon() -> UIImage {
        return UIImage(systemName: "minus.circle.fill")!.withTintColor(.systemRed, renderingMode: .alwaysOriginal)
    }

    static func getInvisibleSFIcon() -> UIImage {
        let configuration = UIImage.SymbolConfiguration(weight: .bold)
        return UIImage(systemName: "circle", withConfiguration: configuration)!.withTintColor(.label, renderingMode: .alwaysOriginal)
    }

    func readableUserStatus() -> String {
        return NCUserStatus.readableUserStatus(fromUserStatus: status)
    }

    func readableUserStatusMessage() -> String {
        return [icon, message].filter { !$0.isEmpty }.joined(separator: "  ")
    }

    func readableUserStatusOrMessage() -> String {
        let userStatusMessage = readableUserStatusMessage()
        return userStatusMessage.isEmpty ? readableUserStatus() : userStatusMessage
    }

    func getSFUserStatusIcon() -> UIImage? {
        switch status {
        case kUserStatusOnline:
            return NCUserStatus.getOnlineSFIcon()
        case kUserStatusAway:
            return NCUserStatus.getAwaySFIcon()
        case kUserStatusBusy:
            return NCUserStatus.getBusySFIcon()
        case kUserStatusDND:
            return NCUserStatus.getDoNotDisturbSFIcon()
        case kUserStatusInvisible:
            return NCUserStatus.getInvisibleSFIcon()
        default:
            return UIImage(systemName: "person.fill.questionmark")
        }
    }

    func hasVisibleStatusIcon() -> Bool {
        return [kUserStatusOnline, kUserStatusAway, kUserStatusBusy, kUserStatusDND, kUserStatusInvisible].contains(status)
    }
}
