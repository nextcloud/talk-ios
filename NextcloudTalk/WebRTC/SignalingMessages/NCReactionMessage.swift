//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers
public class NCReactionMessage: NCSignalingMessage {

    public private(set) var reaction: String?

    public init!(from: String?, to: String?, sid: String?, roomType: String?, payload: [AnyHashable: Any]?) {
        self.reaction = payload?[SignalingKey.reaction] as? String
        super.init(from: from, to: to, sid: sid, type: MessageTypeValue.reaction, payload: payload, roomType: roomType, broadcaster: nil)
    }

    public init(values: [AnyHashable: Any]) {
        let parsed = NCSignalingMessage.parsedValues(from: values)
        self.reaction = parsed.payload?[SignalingKey.reaction] as? String
        super.init(from: parsed.from, to: parsed.to, sid: parsed.sid, type: MessageTypeValue.reaction, payload: parsed.payload, roomType: parsed.roomType, broadcaster: parsed.broadcaster)
    }

    public override func messageType() -> NCSignalingMessageType {
        return .reaction
    }
}
