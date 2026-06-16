//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import WebRTC

public let kRoomTypeVideo = "video"
public let kRoomTypeScreen = "screen"

private enum SignalingKey {
    static let event = "ev"
    static let function = "fn"
    static let sessionId = "sessionId"
    static let message = "message"

    static let data = "data"
    static let sender = "sender"
    static let typeSession = "session"
    static let externalSessionId = "sessionid"

    static let from = "from"
    static let to = "to"
    static let sid = "sid"
    static let type = "type"
    static let action = "action"
    static let payload = "payload"
    static let roomType = "roomType"
    static let nick = "nick"
    static let status = "status"
    static let broadcaster = "broadcaster"
    static let sdp = "sdp"
}

private enum MessageTypeValue {
    static let offer = "offer"
    static let answer = "answer"
    static let prAnswer = "pranswer"
    static let candidate = "candidate"
    static let unshareScreen = "unshareScreen"
    static let removeCandidates = "remove-candidates"
    static let control = "control"
    static let forceMute = "forceMute"
    static let mute = "mute"
    static let unmute = "unmute"
    static let nickChanged = "nickChanged"
    static let raiseHand = "raiseHand"
    static let recording = "recording"
    static let reaction = "reaction"
    static let startedTyping = "startedTyping"
    static let stoppedTyping = "stoppedTyping"
}

@objcMembers
public class NCSignalingMessage: NSObject {

    public private(set) var from: String!
    public private(set) var to: String!
    public private(set) var sid: String?
    public private(set) var type: String!
    public private(set) var payload: [AnyHashable: Any]!
    public private(set) var roomType: String!
    public var broadcaster: String?

    public init(from: String?, to: String?, sid: String?, type: String?, payload: [AnyHashable: Any]?, roomType: String?, broadcaster: String?) {
        self.from = from
        self.to = to
        self.sid = sid
        self.type = type
        self.payload = payload
        self.roomType = roomType
        self.broadcaster = broadcaster
        super.init()
    }

    // MARK: - Parsing

    public class func messageFromJSONString(_ jsonString: String) -> NCSignalingMessage? {
        guard let data = jsonString.data(using: .utf8),
              let values = (try? JSONSerialization.jsonObject(with: data)) as? [AnyHashable: Any] else {
            NSLog("Error parsing signaling message JSON.")
            return nil
        }

        return self.messageFromJSONDictionary(values)
    }

    public class func messageFromJSONDictionary(_ jsonDict: [AnyHashable: Any]) -> NCSignalingMessage? {
        let typeString = jsonDict[SignalingKey.type] as? String

        switch typeString {
        case MessageTypeValue.candidate:
            return NCICECandidateMessage(values: jsonDict)
        case MessageTypeValue.offer, MessageTypeValue.answer:
            return NCSessionDescriptionMessage(values: jsonDict)
        case MessageTypeValue.unshareScreen:
            return NCUnshareScreenMessage(values: jsonDict)
        case MessageTypeValue.control:
            return NCControlMessage(values: jsonDict)
        case MessageTypeValue.mute:
            return NCMuteMessage(values: jsonDict)
        case MessageTypeValue.unmute:
            return NCUnmuteMessage(values: jsonDict)
        case MessageTypeValue.nickChanged:
            return NCNickChangedMessage(values: jsonDict)
        case MessageTypeValue.raiseHand:
            return NCRaiseHandMessage(values: jsonDict)
        case MessageTypeValue.reaction:
            return NCReactionMessage(values: jsonDict)
        default:
            NSLog("Unexpected type: \(typeString ?? "nil")")
            return nil
        }
    }

    public class func messageFromExternalSignalingJSONDictionary(_ jsonDict: [AnyHashable: Any]) -> NCSignalingMessage? {
        let data = jsonDict[SignalingKey.data] as? [AnyHashable: Any]

        switch data?[SignalingKey.type] as? String {
        case MessageTypeValue.unshareScreen:
            return NCUnshareScreenMessage(values: jsonDict)
        case MessageTypeValue.mute:
            return NCMuteMessage(values: jsonDict)
        case MessageTypeValue.unmute:
            return NCUnmuteMessage(values: jsonDict)
        case MessageTypeValue.nickChanged:
            return NCNickChangedMessage(values: jsonDict)
        case MessageTypeValue.raiseHand:
            return NCRaiseHandMessage(values: jsonDict)
        case MessageTypeValue.recording:
            return NCRecordingMessage(values: jsonDict)
        case MessageTypeValue.reaction:
            return NCReactionMessage(values: jsonDict)
        default:
            break
        }

        if data?[SignalingKey.action] as? String == MessageTypeValue.forceMute {
            return NCControlMessage(values: jsonDict)
        }

        let sender = jsonDict[SignalingKey.sender] as? [AnyHashable: Any]
        if sender?[SignalingKey.type] as? String == SignalingKey.typeSession {
            switch data?[SignalingKey.type] as? String {
            case MessageTypeValue.candidate:
                return NCICECandidateMessage(values: jsonDict)
            case MessageTypeValue.offer, MessageTypeValue.answer:
                return NCSessionDescriptionMessage(values: jsonDict)
            default:
                break
            }
        }

        NSLog("Unexpected external signaling message: \(jsonDict)")
        return nil
    }

    public class func getMessageSid() -> String {
        let timeStamp = Date().timeIntervalSince1970
        return NSNumber(value: timeStamp).stringValue
    }

    // MARK: - Serialization

    public override var description: String {
        if let data = self.jsonData(), let string = String(data: data, encoding: .utf8) {
            return string
        }

        return super.description
    }

    func jsonData() -> Data? {
        return try? JSONSerialization.data(withJSONObject: self.messageDict(), options: [])
    }

    func functionJSONSerialization() -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: self.functionDict(), options: []),
              let string = String(data: data, encoding: .utf8) else {
            NSLog("Error serializing JSON")
            return ""
        }

        return string
    }

    public func messageDict() -> [AnyHashable: Any] {
        return [
            SignalingKey.event: SignalingKey.message,
            SignalingKey.function: self.functionJSONSerialization(),
            SignalingKey.sessionId: self.from ?? ""
        ]
    }

    public func functionDict() -> [AnyHashable: Any] {
        return [
            SignalingKey.to: self.to ?? "",
            SignalingKey.roomType: self.roomType ?? "",
            SignalingKey.type: self.type ?? "",
            SignalingKey.sid: self.sid ?? "",
            SignalingKey.payload: self.payload ?? [:]
        ]
    }

    public func messageType() -> NCSignalingMessageType {
        return .unknown
    }

    // MARK: - Helpers

    fileprivate struct ParsedValues {
        let from: String?
        let to: String?
        let sid: String?
        let roomType: String?
        let broadcaster: String?
        let payload: [AnyHashable: Any]?
    }

    // Extracts the common signaling values, taking into account that when using an external signaling
    // server the relevant values are nested in the "data" dictionary and "from" comes from the "sender".
    fileprivate static func parsedValues(from values: [AnyHashable: Any], useDataAsPayload: Bool = false) -> ParsedValues {
        var dataDict = values
        var from = values[SignalingKey.from] as? String
        var payload = values[SignalingKey.payload] as? [AnyHashable: Any]

        if let sender = values[SignalingKey.sender] as? [AnyHashable: Any] {
            from = sender[SignalingKey.externalSessionId] as? String
            dataDict = values[SignalingKey.data] as? [AnyHashable: Any] ?? [:]
            payload = useDataAsPayload ? dataDict : (dataDict[SignalingKey.payload] as? [AnyHashable: Any])
        }

        return ParsedValues(from: from,
                            to: dataDict[SignalingKey.to] as? String,
                            sid: dataDict[SignalingKey.sid] as? String,
                            roomType: dataDict[SignalingKey.roomType] as? String,
                            broadcaster: dataDict[SignalingKey.broadcaster] as? String,
                            payload: payload)
    }
}

// MARK: - ICE candidate

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

// MARK: - Session description

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

// MARK: - Unshare screen

@objcMembers
public class NCUnshareScreenMessage: NCSignalingMessage {

    public init!(from: String?, to: String?, sid: String?, roomType: String?, payload: [AnyHashable: Any]?) {
        super.init(from: from, to: to, sid: sid, type: MessageTypeValue.unshareScreen, payload: payload, roomType: roomType, broadcaster: nil)
    }

    public init(values: [AnyHashable: Any]) {
        let parsed = NCSignalingMessage.parsedValues(from: values)
        super.init(from: parsed.from, to: parsed.to, sid: parsed.sid, type: MessageTypeValue.unshareScreen, payload: [:], roomType: parsed.roomType, broadcaster: parsed.broadcaster)
    }

    public override func messageType() -> NCSignalingMessageType {
        return .unshareScreen
    }
}

// MARK: - Control

@objcMembers
public class NCControlMessage: NCSignalingMessage {

    public init!(from: String?, to: String?, sid: String?, roomType: String?, payload: [AnyHashable: Any]?) {
        super.init(from: from, to: to, sid: sid, type: MessageTypeValue.control, payload: payload, roomType: roomType, broadcaster: nil)
    }

    public init(values: [AnyHashable: Any]) {
        let parsed = NCSignalingMessage.parsedValues(from: values, useDataAsPayload: true)
        super.init(from: parsed.from, to: parsed.to, sid: parsed.sid, type: MessageTypeValue.control, payload: parsed.payload, roomType: parsed.roomType, broadcaster: parsed.broadcaster)
    }

    public override func messageType() -> NCSignalingMessageType {
        return .control
    }
}

// MARK: - Mute

@objcMembers
public class NCMuteMessage: NCSignalingMessage {

    public init!(from: String?, to: String?, sid: String?, roomType: String?, payload: [AnyHashable: Any]?) {
        super.init(from: from, to: to, sid: sid, type: MessageTypeValue.mute, payload: payload, roomType: roomType, broadcaster: nil)
    }

    public init(values: [AnyHashable: Any]) {
        let parsed = NCSignalingMessage.parsedValues(from: values)
        super.init(from: parsed.from, to: parsed.to, sid: parsed.sid, type: MessageTypeValue.mute, payload: parsed.payload, roomType: parsed.roomType, broadcaster: parsed.broadcaster)
    }

    public override func messageType() -> NCSignalingMessageType {
        return .mute
    }
}

// MARK: - Unmute

@objcMembers
public class NCUnmuteMessage: NCSignalingMessage {

    public init!(from: String?, to: String?, sid: String?, roomType: String?, payload: [AnyHashable: Any]?) {
        super.init(from: from, to: to, sid: sid, type: MessageTypeValue.unmute, payload: payload, roomType: roomType, broadcaster: nil)
    }

    public init(values: [AnyHashable: Any]) {
        let parsed = NCSignalingMessage.parsedValues(from: values)
        super.init(from: parsed.from, to: parsed.to, sid: parsed.sid, type: MessageTypeValue.unmute, payload: parsed.payload, roomType: parsed.roomType, broadcaster: parsed.broadcaster)
    }

    public override func messageType() -> NCSignalingMessageType {
        return .unmute
    }
}

// MARK: - Nick changed

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

// MARK: - Raise hand

@objcMembers
public class NCRaiseHandMessage: NCSignalingMessage {

    public init!(from: String?, to: String?, sid: String?, roomType: String?, payload: [AnyHashable: Any]?) {
        super.init(from: from, to: to, sid: sid, type: MessageTypeValue.raiseHand, payload: payload, roomType: roomType, broadcaster: nil)
    }

    public init(values: [AnyHashable: Any]) {
        let parsed = NCSignalingMessage.parsedValues(from: values)
        super.init(from: parsed.from, to: parsed.to, sid: parsed.sid, type: MessageTypeValue.raiseHand, payload: parsed.payload, roomType: parsed.roomType, broadcaster: parsed.broadcaster)
    }

    public override func messageType() -> NCSignalingMessageType {
        return .raiseHand
    }
}

// MARK: - Recording

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

// MARK: - Reaction

@objcMembers
public class NCReactionMessage: NCSignalingMessage {

    public private(set) var reaction: String?

    public init!(from: String?, to: String?, sid: String?, roomType: String?, payload: [AnyHashable: Any]?) {
        super.init(from: from, to: to, sid: sid, type: MessageTypeValue.reaction, payload: payload, roomType: roomType, broadcaster: nil)
    }

    public init(values: [AnyHashable: Any]) {
        let parsed = NCSignalingMessage.parsedValues(from: values)
        super.init(from: parsed.from, to: parsed.to, sid: parsed.sid, type: MessageTypeValue.reaction, payload: parsed.payload, roomType: parsed.roomType, broadcaster: parsed.broadcaster)
    }

    public override func messageType() -> NCSignalingMessageType {
        return .reaction
    }
}

// MARK: - Started typing

@objcMembers
public class NCStartedTypingMessage: NCSignalingMessage {

    public init!(from: String?, sendTo to: String?, withPayload payload: [AnyHashable: Any]?, forRoomType roomType: String?) {
        super.init(from: from, to: to, sid: NCSignalingMessage.getMessageSid(), type: MessageTypeValue.startedTyping, payload: payload, roomType: roomType, broadcaster: nil)
    }

    public init(values: [AnyHashable: Any]) {
        let parsed = NCSignalingMessage.parsedValues(from: values)
        super.init(from: parsed.from, to: parsed.to, sid: parsed.sid, type: MessageTypeValue.startedTyping, payload: parsed.payload, roomType: parsed.roomType, broadcaster: parsed.broadcaster)
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
        return .startedTyping
    }
}

// MARK: - Stopped typing

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
