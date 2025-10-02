//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SwiftyAttributes

@objcMembers public class SignalingParticipant: NSObject {

    public var userId: String?
    public var displayName: String?
    public var signalingSessionId: String?
    public var isFederated: Bool = false

    // actorId/actorType are only available starting >= NC30
    public var actorId: String?
    public var actorType: String?

    public var actor: TalkActor? {
        if let actorId, let actorType {
            return TalkActor(actorId: actorId, actorType: actorType, actorDisplayName: self.displayName)
        } else if let userId, !userId.isEmpty {
            return TalkActor(actorId: userId, actorType: "users", actorDisplayName: self.displayName)
        }

        // TODO: Support guest actors as well

        return nil
    }

    init(withJoinDictionary dict: [AnyHashable: Any]) {
        self.userId = dict["userid"] as? String

        if let userDict = dict["user"] as? [AnyHashable: Any] {
            self.displayName = userDict["displayname"] as? String
        }

        self.signalingSessionId = dict["sessionid"] as? String
        self.isFederated = dict["federated"] as? Bool ?? false

    }

    public func update(withUpdateDictionary dict: [AnyHashable: Any]) {
        self.actorId = dict["actorId"] as? String
        self.actorType = dict["actorType"] as? String
    }
}
