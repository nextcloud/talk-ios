//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

// TODO: Remove when CallKitManager and NCCallController are migrated to swift
@objcMembers
public class ObjcNCAPIVersion: NSObject {
    public static func getAPIVersion(forType type: NCAPIType, withAccount account: TalkAccount) -> Int {
        return NCAPIVersion(forType: type, withAccount: account).rawValue
    }
}

@objc
public enum NCAPIVersion: Int, Comparable {

    case APIv1 = 1
    case APIv2 = 2
    case APIv3 = 3
    case APIv4 = 4

    init(forType type: NCAPIType, withAccount account: TalkAccount) {
        switch type {
        case .conversation:
            if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityConversationV4, forAccountId: account.accountId) {
                self = .APIv4
                return
            }

            if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityChatReadStatus, forAccountId: account.accountId) {
                self = .APIv3
                return
            }

            self = .APIv2
        case .call:
            self = NCAPIVersion(forType: .conversation, withAccount: account)
        case .chat, .reactions, .polls, .breakoutRooms, .federation, .ban, .bots, .recording, .settings, .avatar:
            self = .APIv1
        case .signaling:
            if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilitySignalingV3, forAccountId: account.accountId) {
                self = .APIv3
                return
            }

            if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilitySIPSupport, forAccountId: account.accountId) {
                self = .APIv2
                return
            }

            self = .APIv1
        }
    }

    public static func < (lhs: NCAPIVersion, rhs: NCAPIVersion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
