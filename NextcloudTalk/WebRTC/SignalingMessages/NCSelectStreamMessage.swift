//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

// Raw values are the substream and temporal layer indices of the MCU
enum SimulcastVideoQuality: Int {
    case low = 0
    case medium = 1
    case high = 2
}

public class NCSelectStreamMessage: NCSignalingMessage {

    init(from: String?, to: String?, sid: String?, roomType: String?, quality: SimulcastVideoQuality) {
        // A low frame rate looks bad, so always use the highest temporal layer (same as web)
        let payload: [AnyHashable: Any] = ["substream": quality.rawValue, "temporal": SimulcastVideoQuality.high.rawValue]
        super.init(from: from, to: to, sid: sid, type: MessageTypeValue.selectStream, payload: payload, roomType: roomType, broadcaster: nil)
    }

    public override func messageType() -> NCSignalingMessageType {
        return .selectStream
    }
}
