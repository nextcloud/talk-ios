//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objc public protocol NCExternalSignalingControllerDelegate {
    @objc func externalSignalingController(_ externalSignalingController: NCExternalSignalingController, didReceivedSignalingMessage signalingMessageDict: [AnyHashable: Any])
    @objc func externalSignalingController(_ externalSignalingController: NCExternalSignalingController, didReceivedParticipantListMessage participantListMessageDict: [AnyHashable: Any])
    @objc func externalSignalingControllerShouldRejoinCall(_ externalSignalingController: NCExternalSignalingController)
    @objc func externalSignalingControllerWillRejoinCall(_ externalSignalingController: NCExternalSignalingController)
    @objc func externalSignalingController(_ externalSignalingController: NCExternalSignalingController, shouldSwitchToCall roomToken: String)
}

@objc extension NSNotification {
    public static let ExtSignalingDidReceiveChatMessage = Notification.Name.extSignalingDidReceiveChatMessage
}

extension Notification.Name {
    static let extSignalingDidUpdateParticipants = Notification.Name(rawValue: "NCExternalSignalingControllerDidUpdateParticipantsNotification")
    static let extSignalingDidReceiveJoinOfParticipant = Notification.Name(rawValue: "NCExternalSignalingControllerDidReceiveJoinOfParticipantNotification")
    static let extSignalingDidReceiveLeaveOfParticipant = Notification.Name(rawValue: "NCExternalSignalingControllerDidReceiveLeaveOfParticipantNotification")
    static let extSignalingDidReceiveStartedTyping = Notification.Name(rawValue: "NCExternalSignalingControllerDidReceiveStartedTypingNotification")
    static let extSignalingDidReceiveStoppedTyping = Notification.Name(rawValue: "NCExternalSignalingControllerDidReceiveStoppedTypingNotification")
    static let extSignalingDidReceiveChatMessage = Notification.Name(rawValue: "NCExternalSignalingControllerDidReceiveChatMessageNotification")
}

public typealias SendMessageCompletionBlock = (_ task: URLSessionWebSocketTask?, _ status: NCExternalSignalingSendMessageStatus) -> Void

public enum NCExternalSignalingSendMessageStatus {
    case success
    case socketError
    case applicationError
}

@objcMembers public class NCExternalSignalingController: NSObject, URLSessionWebSocketDelegate, CCCertificateDelegate {

    public weak var delegate: NCExternalSignalingControllerDelegate?

    public var currentRoom: String?

    public private(set) var account: TalkAccount
    public private(set) var disconnected: Bool = true
    public private(set) var hasMCU: Bool = false
    public private(set) var hasChatRelay: Bool = false
    public private(set) var sessionId: String?
    public private(set) var participantsMap = [String: SignalingParticipant]()

    private let initialReconnectInterval = 1
    private let maxReconnectInterval = 16
    private let webSocketTimeoutInterval = 15.0

    private var webSocket: URLSessionWebSocketTask?
    private var serverUrl: String
    private var ticket: String
    private var resumeId: String?
    private var authenticationBackendUrl: String
    private var helloResponseReceived = false
    private var nextMessageId: Int = 0
    private var pendingMessages = [WSMessage]()
    private var helloMessage: WSMessage?
    private var messagesWithCompletionBlock = [WSMessage]()
    private var reconnectInterval: Int = 0
    private var reconnectTimer: Timer?
    private var disconnectTime: TimeInterval?

    init(account: TalkAccount, serverUrl: String, ticket: String) {
        self.account = account
        self.serverUrl = serverUrl
        self.ticket = ticket

        self.authenticationBackendUrl = NCAPIController.sharedInstance().authenticationBackendUrl(for: account)
        self.serverUrl = NCExternalSignalingController.getWebSocketUrl(forServer: serverUrl)

        super.init()

        self.reconnectInterval = self.initialReconnectInterval
        self.connect()
    }

    static func getWebSocketUrl(forServer server: String) -> String {
        var wsUrl = server

        wsUrl = wsUrl.replacingOccurrences(of: "https://", with: "wss://")
        wsUrl = wsUrl.replacingOccurrences(of: "http://", with: "ws://")

        if wsUrl.hasSuffix("/") {
            wsUrl = String(wsUrl.dropLast())
        }

        wsUrl += "/spreed"

        return wsUrl
    }

    // MARK: - WebSocket connection

    func connect() {
        self.connect(force: false)
    }

    func forceConnect() {
        self.connect(force: true)
    }

    func connect(force: Bool) {
        let forceConnect = force || NCRoomsManager.shared.callViewController != nil

        // Do not try to connect if the app is running in the background (unless forcing a connection or in a call)
        if !forceConnect, UIApplication.shared.applicationState == .background {
            NCUtils.log("Trying to create websocket connection while app is in the background")
            self.disconnected = true
            return
        }

        guard let url = URL(string: self.serverUrl) else { return }

        self.invalidateReconnectionTimer()

        self.disconnected = false
        self.nextMessageId = 1
        self.messagesWithCompletionBlock = []
        self.helloResponseReceived = false

        NCUtils.log("Connecting to: \(self.serverUrl)")

        let wsSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        var wsRequest = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: webSocketTimeoutInterval)
        wsRequest.setValue(NCAppBranding.userAgent(), forHTTPHeaderField: "User-Agent")

        if self.resumeId != nil {
            let currentTimestamp = Date().timeIntervalSince1970

            // We are only allowed to resume a session 30s after disconnect
            if self.disconnectTime == nil || (currentTimestamp - (self.disconnectTime ?? 0)) >= 30 {
                NCUtils.log("We have a resumeId, but we disconnected outside of the 30s resume window. Connecting without resumeId.")
                self.resumeId = nil
            }
        }

        let webSocket = wsSession.webSocketTask(with: wsRequest)
        self.webSocket = webSocket

        webSocket.resume()
        self.receiveMessage()
    }

    func reconnect() {
        // Note: Make sure to call reconnect only from the main-thread!
        dispatchPrecondition(condition: .onQueue(.main))

        guard self.reconnectTimer == nil else { return }

        NCUtils.log("Reconnecting to: \(self.serverUrl)")

        self.resetWebSocket()

        // Execute completion blocks on all messages
        for message in self.messagesWithCompletionBlock {
            message.executeCompletionBlock(withStatus: .socketError)
        }

        self.setReconnectionTimer()
    }

    func forceReconnect() {
        DispatchQueue.main.async {
            self.resumeId = nil
            self.currentRoom = nil
            self.reconnect()
        }
    }

    func forceReconnectForRejoin() {
        // In case we force reconnect in order to rejoin the call again, we need to keep the currently joined room.
        // In `helloResponseReceived` we determine that we were in a room and that the sessionId changed, in that case
        // we trigger a re-join in `NCRoomsManager` which takes care of re-joining.

        DispatchQueue.main.async {
            let byeDict = [
                "type": "bye",
                "bye": [:]
            ]

            // Close our current session. Don't leave the room, as that would defeat the above mentioned purpose
            self.send(message: byeDict) { _, _ in
                self.resumeId = nil
                self.reconnect()
            }
        }
    }

    func disconnect() {
        NCUtils.log("Disconnecting from: \(self.serverUrl)")

        self.disconnectTime = Date().timeIntervalSince1970

        DispatchQueue.main.async {
            self.invalidateReconnectionTimer()
            self.resetWebSocket()
        }
    }

    func resetWebSocket() {
        self.webSocket?.cancel()
        self.webSocket = nil
        self.helloResponseReceived = false
        self.helloMessage?.ignoreCompletionBlock()
        self.helloMessage = nil
        self.disconnected = true
    }

    func setReconnectionTimer() {
        self.invalidateReconnectionTimer()

        // Wiggle interval a little bit to prevent all clients from connecting
        // simultaneously in case the server connection is interrupted.
        let interval = self.reconnectInterval - (self.reconnectInterval / 2) + Int.random(in: 1...self.reconnectInterval)
        print("Reconnecting in \(interval)")

        DispatchQueue.main.async {
            self.reconnectTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval), repeats: false, block: { [weak self] _ in
                self?.connect()
            })
        }

        self.reconnectInterval = min(self.reconnectInterval * 2, maxReconnectInterval)
    }

    func invalidateReconnectionTimer() {
        self.reconnectTimer?.invalidate()
        self.reconnectTimer = nil
    }

    // MARK: - WebSocket messages

    func send(message jsonDict: [AnyHashable: Any], withCompletionBlock block: SendMessageCompletionBlock?) {
        let wsMessage = WSMessage(message: jsonDict, completionBlock: block)

        // Add message as pending message if websocket is not connected
        if !self.helloResponseReceived, !wsMessage.isHelloMessage {
            DispatchQueue.main.async {
                if wsMessage.isJoinMessage {
                    // We join a new room, so any message which wasn't send by now is not relevant for the new room anymore
                    self.pendingMessages = []
                }

                NCUtils.log("Trying to send message before we received a hello response -> adding to pendingMessages")
                self.pendingMessages.append(wsMessage)
            }

            return
        }

        self.send(message: wsMessage)
    }

    func send(message wsMessage: WSMessage) {
        guard let webSocket = self.webSocket else { return }

        // Assign messageId and timeout to messages with completionBlocks
        if wsMessage.completionBlock != nil {
            wsMessage.messageId = "\(self.nextMessageId)"
            self.nextMessageId += 1

            if wsMessage.isHelloMessage {
                self.helloMessage?.ignoreCompletionBlock()
                self.helloMessage = wsMessage
            } else {
                self.messagesWithCompletionBlock.append(wsMessage)
            }
        }

        wsMessage.send(withWebSocket: webSocket)
    }

    func sendHelloMessage() {
        var helloDict: [String: Any] = [
            "type": "hello",
            "hello": [
                "version": "1.0",
                "auth": [
                    "url": self.authenticationBackendUrl,
                    "params": [
                        "userid": account.userId,
                        "ticket": ticket
                    ]
                ],
                "features": [
                    "chat-relay"
                ]
            ]
        ]

        if let resumeId = self.resumeId {
            helloDict = [
                "type": "hello",
                "hello": [
                    "version": "1.0",
                    "resumeid": resumeId,
                    "features": [
                        "chat-relay"
                    ]
                ]
            ]
        }

        NCUtils.log("Sending hello message")

        self.send(message: helloDict) { task, status in
            if status == .socketError, task == self.webSocket {
                NCUtils.log("Reconnecting from sendHelloMessage")
                self.reconnect()
            }
        }
    }

    func helloResponseReceived(messageDict: [AnyHashable: Any]) {
        self.helloResponseReceived = true

        NCUtils.log("Hello received with \(self.pendingMessages.count) pending messages")

        let messageId = messageDict["id"] as? String ?? "0"
        self.executeCompletionBlock(forMessageId: messageId, withStatus: .success)

        guard let helloDict = messageDict["hello"] as? [AnyHashable: Any],
              let newSessionId = helloDict["sessionid"] as? String
        else {
            NCUtils.log("Unable to access hello dictionary")
            return
        }

        self.resumeId = helloDict["resumeid"] as? String

        let sessionChanged = self.sessionId != newSessionId
        self.sessionId = newSessionId

        guard let serverDict = helloDict["server"] as? [AnyHashable: Any],
              let serverFeatures = serverDict["features"] as? [String],
              let serverVersion = serverDict["version"] as? String
        else {
            NCUtils.log("Unable to access server dictionary")
            return
        }

        self.hasMCU = serverFeatures.contains(where: { $0 == "mcu" })
        self.hasChatRelay = serverFeatures.contains(where: { $0 == "chat-relay" })

        DispatchQueue.main.async {
            let bgTask = BGTaskHelper.startBackgroundTask(withName: "NCUpdateSignalingVersionTransaction")
            NCDatabaseManager.sharedInstance().setExternalSignalingServerVersion(serverVersion, forAccountId: self.account.accountId)

            // Send pending messages
            for wsMessage in self.pendingMessages {
                self.send(message: wsMessage)
            }

            self.pendingMessages = []

            bgTask.stopBackgroundTask()
        }

        // Re-join if user was in a room
        if let currentRoom, sessionChanged {
            self.delegate?.externalSignalingControllerWillRejoinCall(self)

            NCRoomsManager.shared.rejoinRoomForCall(currentRoom) { _, _, _, _, _ in
                self.delegate?.externalSignalingControllerShouldRejoinCall(self)
            }
        }
    }

    func errorResponseReceived(messageDict: [AnyHashable: Any]) {
        guard let errorDict = messageDict["error"] as? [AnyHashable: Any],
              let errorCode = errorDict["code"] as? String,
              let messageId = messageDict["id"] as? String
        else { return }

        NCUtils.log("Received error response \(errorCode)")

        if errorCode == "no_such_session" || errorCode == "too_many_requests" {
            // We could not resume the previous session, but the websocket is still alive -> resend the hello message without a resumeId
            self.resumeId = nil
            self.sendHelloMessage()

            return
        } else if errorCode == "already_joined" {
            // We already joined this room on the signaling server
            guard let detailsDict = errorDict["details"] as? [AnyHashable: Any],
                  let roomDict = detailsDict["room"] as? [AnyHashable: Any],
                  let roomId = roomDict["roomid"] as? String
            else { return }

            // If we are aware that we were in this room before, we should treat this as a success
            if currentRoom == roomId {
                self.executeCompletionBlock(forMessageId: messageId, withStatus: .success)
                return
            }
        }

        self.executeCompletionBlock(forMessageId: messageId, withStatus: .applicationError)
    }

    func joinRoom(withRoomId roomId: String, withSessionId sessionId: String, withFederation federationDict: [AnyHashable: Any]?, withCompletionBlock block: ((_ error: NSError?) -> Void)?) {
        if self.disconnected {
            NCUtils.log("Joining room \(roomId), but the websocket is disconnected.")
        }

        if self.webSocket == nil {
            NCUtils.log("Joining room \(roomId), but the websocket is nil.")
        }

        var messageDict: [AnyHashable: Any] = [
            "type": "room",
            "room": [
                "roomid": roomId,
                "sessionid": sessionId
            ]
        ]

        if let federationDict {
            messageDict = [
                "type": "room",
                "room": [
                    "roomid": roomId,
                    "sessionid": sessionId,
                    "federation": federationDict
                ]
            ]
        }

        self.send(message: messageDict) { task, status in
            if status == .socketError, task == self.webSocket {
                // Reconnect if this is still the same socket we tried to send the message on
                NCUtils.log("Reconnect from joinRoom")

                // When we failed to join a room, we shouldn't try to resume a session but instead do a force reconnect
                self.forceReconnect()
            }

            if let block {
                if status != .success {
                    block(NSError(domain: NSCocoaErrorDomain, code: 0))
                } else {
                    block(nil)
                }
            }
        }
    }

    func leaveRoom(withRoomId roomId: String) {
        if self.currentRoom == roomId {
            self.currentRoom = nil
            self.joinRoom(withRoomId: "", withSessionId: "", withFederation: nil, withCompletionBlock: nil)
        } else {
            print("External signaling: Not leaving because it's not the room we joined")
        }
    }

    func sendCallMessage(_ message: NCSignalingMessage) {
        let messageDict: [AnyHashable: Any] = [
            "type": "message",
            "message": [
                "recipient": [
                    "type": "session",
                    "sessionid": message.to!
                ],
                "data": message.functionDict()
            ]
        ]

        self.send(message: messageDict, withCompletionBlock: nil)
    }

    func sendSendOfferMessage(withSessionId sessionId: String, andRoomType roomType: String) {
        let messageDict: [AnyHashable: Any] = [
            "type": "message",
            "message": [
                "recipient": [
                    "type": "session",
                    "sessionid": sessionId
                ],
                "data": [
                    "type": "sendoffer",
                    "roomType": roomType
                ]
            ]
        ]

        self.send(message: messageDict, withCompletionBlock: nil)
    }

    func requestOffer(forSessionId sessionId: String, andRoomType roomType: String) {
        let messageDict: [AnyHashable: Any] = [
            "type": "message",
            "message": [
                "recipient": [
                    "type": "session",
                    "sessionid": sessionId
                ],
                "data": [
                    "type": "requestoffer",
                    "roomType": roomType
                ]
            ]
        ]

        self.send(message: messageDict, withCompletionBlock: nil)
    }

    func sendRoomMessage(ofType messageType: String, andRoomType roomType: String) {
        let messageDict: [AnyHashable: Any] = [
            "type": "message",
            "message": [
                "recipient": [
                    "type": "room"
                ],
                "data": [
                    "type": messageType,
                    "roomType": roomType
                ]
            ]
        ]

        self.send(message: messageDict, withCompletionBlock: nil)
    }

    func roomMessageReceived(messageDict: [AnyHashable: Any]) {
        guard let roomDict = messageDict["room"] as? [AnyHashable: Any],
              let newRoomId = roomDict["roomid"] as? String
        else { return }

        // Only reset the participant map when the room actually changed
        // Otherwise we would loose participant information for example when a recording is started
        if self.currentRoom != newRoomId {
            self.participantsMap = [:]
            self.currentRoom = newRoomId
        }

        if let messageId = messageDict["id"] as? String {
            self.executeCompletionBlock(forMessageId: messageId, withStatus: .success)
        }
    }

    func eventMessageReceived(eventDict: [AnyHashable: Any]) {
        let eventTarget = eventDict["target"] as? String

        if eventTarget == "room" {
            self.processRoomEvent(eventDict: eventDict)
        } else if eventTarget == "roomlist" {
            self.processRoomListEvent(eventDict: eventDict)
        } else if eventTarget == "participants" {
            self.processRoomParticipantsEvents(eventDict: eventDict)
        } else {
            print("Unsupported event target: \(eventDict)")
        }
    }

    func processRoomEvent(eventDict: [AnyHashable: Any]) {
        guard let eventType = eventDict["type"] as? String
        else { return }

        if eventType == "join" {
            guard let joinDict = eventDict["join"] as? [[AnyHashable: Any]]
            else { return }

            for participantDict in joinDict {
                let participant = SignalingParticipant(withJoinDictionary: participantDict)

                if !participant.isFederated, participant.userId == self.account.userId {
                    print("App user joined room")
                    continue
                }

                // Only notify if another participant joined the room and not ourselves from a different device
                print("Participant joined room")

                guard let currentRoom, let signalingSessionId = participant.signalingSessionId
                else { continue }

                var userInfo = [String: String]()
                userInfo["roomToken"] = currentRoom
                userInfo["sessionId"] = signalingSessionId

                self.participantsMap[signalingSessionId] = participant
                NotificationCenter.default.post(name: .extSignalingDidReceiveJoinOfParticipant, object: self, userInfo: userInfo)
            }
        } else if eventType == "leave" {
            guard let leftSessions = eventDict["leave"] as? [String]
            else { return }

            for sessionId in leftSessions {
                guard let participant = self.getParticipant(fromSessionId: sessionId)
                else { return }

                self.participantsMap.removeValue(forKey: sessionId)

                guard let currentRoom else { continue }

                if participant.signalingSessionId == self.sessionId || (participant.isFederated && participant.userId == self.account.userId) {
                    // Ignore own session
                    continue
                }

                var userInfo = [String: String]()
                userInfo["roomToken"] = currentRoom
                userInfo["sessionId"] = sessionId

                if let userId = participant.userId {
                    userInfo["userId"] = userId
                }

                NotificationCenter.default.post(name: .extSignalingDidReceiveLeaveOfParticipant, object: self, userInfo: userInfo)
            }
        } else if eventType == "message", let wrappedMessage = eventDict["message"] as? [AnyHashable: Any] {
            self.processRoomMessageEvent(messageDict: wrappedMessage)
        } else if eventType == "switchto", let wrappedMessage = eventDict["switchto"] as? [AnyHashable: Any] {
            self.processSwitchToMessageEvent(messageDict: wrappedMessage)
        } else {
            print("Unknown room event: \(eventDict)")
        }
    }

    func processRoomMessageEvent(messageDict: [AnyHashable: Any]) {
        guard let dataDict = messageDict["data"] as? [AnyHashable: Any],
              let messageType = dataDict["type"] as? String
        else { return }

        if messageType == "chat" {
            print("Chat message received")
            NotificationCenter.default.post(name: .extSignalingDidReceiveChatMessage, object: self, userInfo: messageDict)
        } else if messageType == "recording" {
            self.delegate?.externalSignalingController(self, didReceivedSignalingMessage: messageDict)
        } else {
            print("Unknown room message type \(messageDict)")
        }
    }

    func processSwitchToMessageEvent(messageDict: [AnyHashable: Any]) {
        let roomToken = messageDict["roomid"] as? String

        if let roomToken, !roomToken.isEmpty {
            self.delegate?.externalSignalingController(self, shouldSwitchToCall: roomToken)
        } else {
            print("Unknown switchTo message: \(messageDict)")
        }
    }

    func processRoomListEvent(eventDict: [AnyHashable: Any]) {
        print("Refresh room list.")
    }

    func processRoomParticipantsEvents(eventDict: [AnyHashable: Any]) {
        guard let eventType = eventDict["type"] as? String
        else { return }

        if eventType == "update" {
            guard let updateDict = eventDict["update"] as? [AnyHashable: Any]
            else { return }

            self.delegate?.externalSignalingController(self, didReceivedParticipantListMessage: updateDict)

            var userInfo = [String: Any]()

            if let roomToken = updateDict["roomid"] as? String {
                userInfo["roomToken"] = roomToken
            }

            if let users = updateDict["users"] as? [[AnyHashable: Any]] {
                for userDict in users {
                    if let sessionId = userDict["sessionId"] as? String {
                        self.getParticipant(fromSessionId: sessionId)?.update(withUpdateDictionary: userDict)
                    }
                }

                userInfo["users"] = users
            }

            NotificationCenter.default.post(name: .extSignalingDidUpdateParticipants, object: self, userInfo: userInfo)
        } else {
            print("Unknown room event: \(eventDict)")
        }
    }

    func messageReceived(messageDict: [AnyHashable: Any]) {
        guard let dataDict = messageDict["data"] as? [AnyHashable: Any],
              let messageType = dataDict["type"] as? String
        else { return }

        if messageType == "startedTyping" || messageType == "stoppedTyping" {
            var userInfo = [String: Any]()

            guard let sender = messageDict["sender"] as? [AnyHashable: Any],
                  let fromSession = sender["sessionid"] as? String,
                  let currentRoom
            else { return }

            userInfo["roomToken"] = currentRoom
            userInfo["sessionId"] = fromSession

            if let fromUser = sender["userid"] as? String {
                userInfo["userId"] = fromUser
            }

            if let participant = self.getParticipant(fromSessionId: fromSession) {
                userInfo["isFederated"] = participant.isFederated

                if let displayName = participant.displayName {
                    userInfo["displayName"] = displayName
                }
            }

            if messageType == "startedTyping" {
                NotificationCenter.default.post(name: .extSignalingDidReceiveStartedTyping, object: self, userInfo: userInfo)
            } else {
                NotificationCenter.default.post(name: .extSignalingDidReceiveStoppedTyping, object: self, userInfo: userInfo)
            }
        } else {
            self.delegate?.externalSignalingController(self, didReceivedSignalingMessage: messageDict)
        }
    }

    // MARK: - Completion blocks

    func executeCompletionBlock(forMessageId messageId: String, withStatus status: NCExternalSignalingSendMessageStatus) {
        DispatchQueue.main.async {
            if let helloMessage = self.helloMessage, helloMessage.messageId == messageId {
                self.helloMessage?.executeCompletionBlock(withStatus: status)
                self.helloMessage = nil

                return
            }

            if let message = self.messagesWithCompletionBlock.first(where: { messageId == $0.messageId }) {
                message.executeCompletionBlock(withStatus: status)
                self.messagesWithCompletionBlock.removeAll(where: { messageId == $0.messageId })
            }
        }
    }

    // MARK: - CCCertificateDelegate

    public func trustedCerticateAccepted() {
        self.reconnect()
    }

    // MARK: - NSURLSessionWebSocketDelegate

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async {
            guard webSocketTask == self.webSocket else { return }

            NCUtils.log("WebSocket connected!")
            self.reconnectInterval = self.initialReconnectInterval
            self.sendHelloMessage()
        }
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async {
            guard webSocketTask == self.webSocket else { return }

            NCUtils.log("WebSocket didCloseWithCode: \(closeCode) reason: \(reason, default: "Unknown")")
            self.reconnect()
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        DispatchQueue.main.async {
            guard task == self.webSocket else { return }

            if let error = error as? URLError, error.code == .serverCertificateUntrusted {
                NCUtils.log("WebSocket session didCompleteWithError: \(error)")

                DispatchQueue.main.async {
                    CCCertificate.sharedManager()
                        .presentViewControllerCertificate(
                            withTitle: error.localizedDescription,
                            viewController: NCUserInterfaceController.sharedInstance().mainViewController,
                            delegate: self)
                }

                return
            }

            if let error {
                NCUtils.log("WebSocket session didCompleteWithError: \(error)")
                self.reconnect()
            }
        }
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // The pinning check
        if CCCertificate.sharedManager().checkTrustedChallenge(challenge) {
            completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    public func receiveMessage() {
        guard let webSocket else { return }

        let receivingWebSocket = webSocket

        webSocket.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let string):
                    self.handleReceivedMessage(message: string.data(using: .utf8)!)
                case .data(let data):
                    self.handleReceivedMessage(message: data)
                @unknown default:
                    break
                }

                self.receiveMessage()
            case .failure(let error):
                DispatchQueue.main.async {
                    // Only try to reconnect if the webSocket is still the one we tried to receive a message on
                    guard receivingWebSocket == self.webSocket else { return }

                    if let error = error as? URLError, error.code == .serverCertificateUntrusted {
                        // The error is handled in `didCompleteWithError` already, don't try to reconnect from here
                        return
                    }

                    NCUtils.log("WebSocket receiveMessageWithCompletionHandler error \(error)")
                    self.reconnect()
                }
            }
        }
    }

    private func handleReceivedMessage(message: Data) {
        guard let messageDict = self.getWebSocketMessageFromJSONData(jsonData: message),
              let messageType = messageDict["type"] as? String
        else { return }

        if messageType == "hello" {
            self.helloResponseReceived(messageDict: messageDict)
        } else if messageType == "error" {
            self.errorResponseReceived(messageDict: messageDict)
        } else if messageType == "room" {
            self.roomMessageReceived(messageDict: messageDict)
        } else if messageType == "event", let wrappedMessage = messageDict["event"] as? [AnyHashable: Any] {
            self.eventMessageReceived(eventDict: wrappedMessage)
        } else if messageType == "message", let wrappedMessage = messageDict["message"] as? [AnyHashable: Any] {
            self.messageReceived(messageDict: wrappedMessage)
        } else if messageType == "control", let wrappedMessage = messageDict["control"] as? [AnyHashable: Any] {
            self.messageReceived(messageDict: wrappedMessage)
        }

        // Completion block for messageId should have been handled already at this point
        if let messageId = messageDict["id"] as? String {
            self.executeCompletionBlock(forMessageId: messageId, withStatus: .applicationError)
        }
    }

    // MARK: - Utils

    func getParticipant(fromSessionId sessionId: String) -> SignalingParticipant? {
        return self.participantsMap[sessionId]
    }

    func getWebSocketMessageFromJSONData(jsonData: Data) -> [AnyHashable: Any]? {
        let messageDict = try? JSONSerialization.jsonObject(with: jsonData) as? [AnyHashable: Any]
        return messageDict
    }

}
