//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

public let kRoomTypeVideo = "video"
public let kRoomTypeScreen = "screen"

enum SignalingKey {
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
    static let reaction = "reaction"
}

enum MessageTypeValue {
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

    struct ParsedValues {
        let from: String?
        let to: String?
        let sid: String?
        let roomType: String?
        let broadcaster: String?
        let payload: [AnyHashable: Any]?
    }

    // Extracts the common signaling values, taking into account that when using an external signaling
    // server the relevant values are nested in the "data" dictionary and "from" comes from the "sender".
    static func parsedValues(from values: [AnyHashable: Any], useDataAsPayload: Bool = false) -> ParsedValues {
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
