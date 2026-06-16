//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers
public class NCStoppedTypingMessage: NCSignalingMessage {

    public init!(from: String?, sendTo to: String?, withPayload payload: [AnyHashable: Any]?, forRoomType roomType: String?) {
        super.init(from: from, to: to, sid: NCSignalingMessage.getMessageSid(), type: MessageTypeValue.stoppedTyping, payload: payload, roomType: roomType, broadcaster: nil)
    }

    public init(values: [AnyHashable: Any]) {
        let parsed = NCSignalingMessage.parsedValues(from: values)
        super.init(from: parsed.from, to: parsed.to, sid: parsed.sid, type: MessageTypeValue.stoppedTyping, payload: parsed.payload, roomType: parsed.roomType, broadcaster: parsed.broadcaster)
    }

    public override func functionDict() -> [AnyHashable: Any] {
        return [
            SignalingKey.to: self.to ?? "",
            SignalingKey.roomType: self.roomType ?? "",
            SignalingKey.type: self.type ?? "",
            SignalingKey.payload: self.payload ?? [:]
        ]
    }

    public override func messageType() -> NCSignalingMessageType {
        return .stoppedTyping
    }
}
