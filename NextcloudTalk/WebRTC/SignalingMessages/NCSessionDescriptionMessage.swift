//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import WebRTC

@objcMembers
public class NCSessionDescriptionMessage: NCSignalingMessage {

    public private(set) var sessionDescription: RTCSessionDescription!
    public private(set) var nick: String?

    public init!(sessionDescription: RTCSessionDescription, from: String?, to: String?, sid: String?, roomType: String?, broadcaster: String?, nick: String?) {
        let type = NCSessionDescriptionMessage.type(for: sessionDescription)

        self.sessionDescription = sessionDescription
        self.nick = nick
        super.init(from: from,
                   to: to,
                   sid: sid,
                   type: type,
                   payload: [SignalingKey.type: type, SignalingKey.sdp: sessionDescription.sdp],
                   roomType: roomType,
                   broadcaster: broadcaster)
    }

    public init(values: [AnyHashable: Any]) {
        var dataDict = values
        var from = values[SignalingKey.from] as? String

        if let sender = values[SignalingKey.sender] as? [AnyHashable: Any] {
            from = sender[SignalingKey.externalSessionId] as? String
            dataDict = values[SignalingKey.data] as? [AnyHashable: Any] ?? [:]
        }

        let payloadDict = dataDict[SignalingKey.payload] as? [AnyHashable: Any] ?? [:]
        let description = NCSessionDescriptionMessage.sessionDescription(fromJSONDictionary: payloadDict)
        let type = NCSessionDescriptionMessage.type(for: description)

        self.sessionDescription = description
        self.nick = payloadDict[SignalingKey.nick] as? String
        super.init(from: from,
                   to: dataDict[SignalingKey.to] as? String,
                   sid: dataDict[SignalingKey.sid] as? String,
                   type: type,
                   payload: [SignalingKey.type: type, SignalingKey.sdp: description.sdp],
                   roomType: dataDict[SignalingKey.roomType] as? String,
                   broadcaster: dataDict[SignalingKey.broadcaster] as? String)
    }

    public override func functionDict() -> [AnyHashable: Any] {
        return [
            SignalingKey.to: self.to ?? "",
            SignalingKey.roomType: self.roomType ?? "",
            SignalingKey.type: self.type ?? "",
            SignalingKey.sid: self.sid ?? "",
            SignalingKey.broadcaster: self.broadcaster ?? "",
            SignalingKey.payload: [
                SignalingKey.type: self.type ?? "",
                SignalingKey.sdp: self.sessionDescription.sdp,
                SignalingKey.nick: self.nick ?? ""
            ]
        ]
    }

    public override func messageType() -> NCSignalingMessageType {
        return self.type == MessageTypeValue.offer ? .offer : .answer
    }

    private static func type(for sessionDescription: RTCSessionDescription) -> String {
        switch sessionDescription.type {
        case .offer:
            return MessageTypeValue.offer
        case .answer:
            return MessageTypeValue.answer
        default:
            assertionFailure("Unexpected SDP type")
            return ""
        }
    }

    private static func sessionDescription(fromJSONDictionary dict: [AnyHashable: Any]) -> RTCSessionDescription {
        let typeString = dict[SignalingKey.type] as? String ?? ""
        let sdp = dict[SignalingKey.sdp] as? String ?? ""

        let type: RTCSdpType
        switch typeString {
        case MessageTypeValue.answer:
            type = .answer
        case MessageTypeValue.prAnswer:
            type = .prAnswer
        default:
            type = .offer
        }

        return RTCSessionDescription(type: type, sdp: sdp)
    }
}
