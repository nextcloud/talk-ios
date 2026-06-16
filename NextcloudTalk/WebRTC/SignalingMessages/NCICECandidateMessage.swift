//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import WebRTC

@objcMembers
public class NCICECandidateMessage: NCSignalingMessage {

    public private(set) var candidate: RTCIceCandidate!

    public init!(candidate: RTCIceCandidate, from: String?, to: String?, sid: String?, roomType: String?, broadcaster: String?) {
        self.candidate = candidate
        super.init(from: from, to: to, sid: sid, type: MessageTypeValue.candidate, payload: [:], roomType: roomType, broadcaster: broadcaster)
    }

    public init(values: [AnyHashable: Any]) {
        var dataDict = values
        var from = values[SignalingKey.from] as? String

        if let sender = values[SignalingKey.sender] as? [AnyHashable: Any] {
            from = sender[SignalingKey.externalSessionId] as? String
            dataDict = values[SignalingKey.data] as? [AnyHashable: Any] ?? [:]
        }

        let payloadDict = dataDict[SignalingKey.payload] as? [AnyHashable: Any] ?? [:]
        let candidateDict = payloadDict[MessageTypeValue.candidate] as? [AnyHashable: Any] ?? [:]

        self.candidate = NCICECandidateMessage.iceCandidate(fromJSONDictionary: candidateDict)
        super.init(from: from,
                   to: dataDict[SignalingKey.to] as? String,
                   sid: dataDict[SignalingKey.sid] as? String,
                   type: MessageTypeValue.candidate,
                   payload: [:],
                   roomType: dataDict[SignalingKey.roomType] as? String,
                   broadcaster: dataDict[SignalingKey.broadcaster] as? String)
    }

    public override func functionDict() -> [AnyHashable: Any] {
        return [
            SignalingKey.to: self.to ?? "",
            SignalingKey.roomType: self.roomType ?? "",
            SignalingKey.type: self.type ?? "",
            SignalingKey.sid: self.sid ?? "",
            SignalingKey.payload: [
                SignalingKey.type: self.type ?? "",
                MessageTypeValue.candidate: NCICECandidateMessage.jsonDictionary(from: self.candidate)
            ]
        ]
    }

    public override func messageType() -> NCSignalingMessageType {
        return .candidate
    }

    private static func iceCandidate(fromJSONDictionary dict: [AnyHashable: Any]) -> RTCIceCandidate {
        let mid = dict["sdpMid"] as? String
        let sdp = dict["candidate"] as? String ?? ""
        let mLineIndex = (dict["sdpMLineIndex"] as? NSNumber)?.int32Value ?? 0

        return RTCIceCandidate(sdp: sdp, sdpMLineIndex: mLineIndex, sdpMid: mid)
    }

    private static func jsonDictionary(from candidate: RTCIceCandidate) -> [AnyHashable: Any] {
        return [
            "sdpMLineIndex": NSNumber(value: candidate.sdpMLineIndex),
            "sdpMid": candidate.sdpMid ?? "",
            "candidate": candidate.sdp
        ]
    }
}
