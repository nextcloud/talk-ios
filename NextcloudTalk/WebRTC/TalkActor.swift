//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SwiftyAttributes

@objcMembers public class TalkActor: NSObject {

    public var id: String?
    public var type: String?

    /// Contains the raw displayName that was used to create the TalkActor
    public var rawDisplayName: String

    /// Takes deleted users and guests into account and returns the correct displayName
    /// Does **not** append a potential `cloudId`
    public var displayName: String {
        if rawDisplayName.isEmpty {
            if isDeleted {
                return NSLocalizedString("Deleted user", comment: "")
            } else {
                return NSLocalizedString("Guest", comment: "")
            }
        }

        return rawDisplayName
    }

    /// Takes deleted users and guests into account and returns it as `secondaryLabel`
    /// This also appends a potential `cloudId` as `tertiaryLabel` in parentheses
    public var attributedDisplayName: NSMutableAttributedString {
        let displayName = self.displayName
        let titleLabel = displayName.withTextColor(.secondaryLabel)

        if let remoteServer = cloudId {
            let remoteServerString = " (\(String(remoteServer)))"
            titleLabel.append(remoteServerString.withTextColor(.tertiaryLabel))
        } else if isGuest, !rawDisplayName.isEmpty {
            // Show guest indication only when we did not use the default "Guest" name
            let guestString = " (\(NSLocalizedString("guest", comment: "")))"
            titleLabel.append(guestString.withTextColor(.tertiaryLabel))
        }

        return titleLabel
    }

    init(actorId: String? = nil, actorType: String? = nil, actorDisplayName: String? = nil) {
        self.id = actorId
        self.type = actorType
        self.rawDisplayName = actorDisplayName ?? ""
    }

    public var isDeleted: Bool {
        return id == "deleted_users" && type == "deleted_users"
    }

    public var isFederated: Bool {
        return type == "federated_users"
    }

    public var isGuest: Bool {
        return type == "guests" || type == "emails"
    }

    public var cloudId: String? {
        guard isFederated, let remoteServer = id?.split(separator: "@").last else { return nil }

        return String(remoteServer)
    }
}
