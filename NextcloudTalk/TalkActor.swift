//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class TalkActor: NSObject {

    public var id: String?
    public var type: String?
    public var displayName: String

    public var displayNameProcessed: String {
        if displayName.isEmpty {
            if id == "deleted_users", type == "deleted_users" {
                return NSLocalizedString("Deleted user", comment: "")
            } else {
                return NSLocalizedString("Guest", comment: "")
            }
        }

        return displayName
    }

    init(actorId: String? = nil, actorType: String? = nil, actorDisplayName: String? = nil) {
        self.id = actorId
        self.type = actorType
        self.displayName = actorDisplayName ?? ""
    }

    public var isDeleted: Bool {
        return id == "deleted_users" && type == "deleted_users"
    }

    public var isFederated: Bool {
        return type == "federated_users"
    }

    public var cloudId: String? {
        guard isFederated, let remoteServer = id?.split(separator: "@").last else { return nil }

        return String(remoteServer)
    }
}
