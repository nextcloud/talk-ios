//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers
public class NCRecordingMessage: NCSignalingMessage {

    public private(set) var status: Int = 0

    public init(values: [AnyHashable: Any]) {
        let dataDict = values[SignalingKey.data] as? [AnyHashable: Any] ?? [:]
        let recordingDict = dataDict[MessageTypeValue.recording] as? [AnyHashable: Any] ?? [:]

        if let number = recordingDict[SignalingKey.status] as? NSNumber {
            self.status = number.intValue
        } else if let string = recordingDict[SignalingKey.status] as? String {
            self.status = (string as NSString).integerValue
        }

        super.init(from: nil, to: nil, sid: nil, type: MessageTypeValue.recording, payload: recordingDict, roomType: nil, broadcaster: nil)
    }

    public override func messageType() -> NCSignalingMessageType {
        return .recording
    }
}
