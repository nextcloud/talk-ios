//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class BannedActor: NSObject {

    public var banId: Int = 0
    public var moderatorActorType: String?
    public var moderatorActorId: String?
    public var moderatorDisplayName: String?
    public var bannedType: String?
    public var bannedId: String?
    public var bannedDisplayName: String?
    public var bannedTime: Int?
    public var internalNote: String?

    init(dictionary: [String: Any]) {
        super.init()

        self.banId = dictionary["id"] as? Int ?? 0
        self.moderatorActorType = dictionary["moderatorActorType"] as? String
        self.moderatorActorId = dictionary["moderatorActorId"] as? String
        self.moderatorDisplayName = dictionary["moderatorDisplayName"] as? String
        self.bannedType = dictionary["bannedActorType"] as? String
        self.bannedId = dictionary["bannedActorId"] as? String
        self.bannedDisplayName = dictionary["bannedDisplayName"] as? String
        self.bannedTime = dictionary["bannedTime"] as? Int
        self.internalNote = dictionary["internalNote"] as? String
    }
}
