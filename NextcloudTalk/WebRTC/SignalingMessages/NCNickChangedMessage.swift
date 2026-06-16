//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers
public class NCNickChangedMessage: NCSignalingMessage {

    public init!(from: String?, to: String?, sid: String?, roomType: String?, payload: [AnyHashable: Any]?) {
        super.init(from: from, to: to, sid: sid, type: MessageTypeValue.nickChanged, payload: payload, roomType: roomType, broadcaster: nil)
    }

    public init(values: [AnyHashable: Any]) {
        let parsed = NCSignalingMessage.parsedValues(from: values)
        super.init(from: parsed.from, to: parsed.to, sid: parsed.sid, type: MessageTypeValue.nickChanged, payload: parsed.payload, roomType: parsed.roomType, broadcaster: parsed.broadcaster)
    }

    public override func messageType() -> NCSignalingMessageType {
        return .nickChanged
    }
}
