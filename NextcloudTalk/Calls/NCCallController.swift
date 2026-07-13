//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import WebRTC

internal protocol NCCallControllerDelegate: NSObjectProtocol {

    func callControllerDidJoinCall(_ callController: NCCallController)
    func callControllerDidFailedJoiningCall(_ callController: NCCallController, statusCode: Int, errorReason: String)
    func callControllerDidEndCall(_ callController: NCCallController)
    func callController(_ callController: NCCallController, peerJoined peer: NCPeerConnection)
    func callController(_ callController: NCCallController, peerLeft peer: NCPeerConnection)
    func callController(_ callController: NCCallController, didCreateLocalAudioTrack audioTrack: RTCAudioTrack?)
    func callController(_ callController: NCCallController, didCreateLocalVideoTrack videoTrack: RTCVideoTrack?)
    func callController(_ callController: NCCallController, didCreateCameraController cameraController: NCCameraController)
    func callController(_ callController: NCCallController, userPermissionsChanged permissions: NCPermission)
    func callController(_ callController: NCCallController, didAddStream remoteStream: RTCMediaStream, ofPeer remotePeer: NCPeerConnection)
    func callController(_ callController: NCCallController, didRemoveStream remoteStream: RTCMediaStream, ofPeer remotePeer: NCPeerConnection)
    func callController(_ callController: NCCallController, iceStatusChanged state: RTCIceConnectionState, ofPeer peer: NCPeerConnection)
    func callController(_ callController: NCCallController, didAddDataChannel dataChannel: RTCDataChannel)
    func callController(_ callController: NCCallController, didReceiveDataChannelMessage message: String, fromPeer peer: NCPeerConnection)
    func callController(_ callController: NCCallController, didReceiveNick nick: String, fromPeer peer: NCPeerConnection)
    func callController(_ callController: NCCallController, didReceiveUnshareScreenFromPeer peer: NCPeerConnection)
    func callController(_ callController: NCCallController, didReceiveForceMuteActionForPeerId peerId: String)
    func callController(_ callController: NCCallController, didReceiveReaction reaction: String, fromPeer peer: NCPeerConnection)
    func callControllerIsReconnectingCall(_ callController: NCCallController)
    func callControllerWants(toHangUpCall callController: NCCallController)
    func callControllerDidChangeRecording(_ callController: NCCallController)
    func callControllerDidDrawFirstLocalFrame(_ callController: NCCallController)
    func callControllerDidChangeScreenrecording(_ callController: NCCallController)
    func callController(_ callController: NCCallController, isSwitchingToCall token: String, withAudioEnabled audioEnabled: Bool, andVideoEnabled videoEnabled: Bool)
}

@objcMembers
internal class NCCallController: NSObject, NCPeerConnectionDelegate, NCSignalingControllerObserver, NCExternalSignalingControllerDelegate, NCCameraControllerDelegate {

    typealias PeerKey = String

    public weak var delegate: NCCallControllerDelegate?

    private static var kNCMediaStreamId = "NCMS"
    private static var kNCAudioTrackId = "NCa0"
    private static var kNCVideoTrackId = "NCv0"
    private static var kNCScreenTrackId = "NCs0"

    private let room: NCRoom
    private let account: TalkAccount
    private let userSessionId: String
    private let isAudioOnly: Bool

    // TODO: Default true?
    public var disableAudioAtStart: Bool = false
    public var disableVideoAtStart: Bool = false
    public var silentCall: Bool = false
    public var silentFor = [String]()
    public var recordingConsent: Bool = false
    public var screensharingActive: Bool = false

    private var isLeavingCall: Bool = false
    private var preparedForRejoin: Bool = false
    private var joinedCallOnce: Bool = false
    private var shouldRejoinCallUsingInternalSignaling: Bool = false

    private var signalingController: NCSignalingController
    private var externalSignalingController: NCExternalSignalingController?
    private var joinCallTask: URLSessionTask?
    private var getPeersForCallTask: URLSessionTask?
    private var joinCallAttempts = 0
    private var speaking = false
    private var userInCall = 0 // TODO: Do we have a type for that?
    private var sendCurrentStateTimer: Timer?

    /*
      // Use SignalingParticipant here?

      "inCall": #INTEGER#,
      "lastPing": #INTEGER#,
      "sessionId": #STRING#,
      "participantType": #INTEGER#,
      "userId": #STRING#,
      "nextcloudSessionId": #STRING#,
      "internal": #BOOLEAN#,
      "participantPermissions": #INTEGER#,
     */
    private var usersInRoom = [[String: Any]]()

    /*
     // Used for internal signaling, API call

      "actorId": "string",
      "actorType": "string",
      "displayName": "string",
      "lastPing": 0,
      "sessionId": "string",
      "token": "string"
     */
    private var peersInCall = [[String: Any]]()

    private var connectionsDict = [PeerKey: NCPeerConnection]()
    private var pendingOffersDict = [PeerKey: Timer]()

    private var sessionsInCall = [String]()
    private var cameraController: NCCameraController?

    #if targetEnvironment(simulator)
    private var simulatorVideoCapturer: SimulatorVideoCapturer?
    #endif

    private var recorder: AVAudioRecorder?
    private var micAudioLevelTimer: Timer?
    private var publisherPeerConnection: NCPeerConnection?
    private var screenPublisherPeerConnection: NCPeerConnection?
    private var localAudioTrack: RTCAudioTrack?
    private var localVideoTrack: RTCVideoTrack?
    private var localScreenTrack: RTCVideoTrack?
    private var localVideoCaptureController: ARDCaptureController?

    private let screensharingController = NCScreensharingController()

    // TODO: Since sessionId is optional on ext. signaling controller, should this be optional?
    public var signalingSessionId: String {
        if let externalSignalingController {
            return externalSignalingController.sessionId ?? ""
        }

        return self.userSessionId
    }

    private var joinCallFlags: CallFlag {
        var flags: CallFlag = [.inCall]

        if room.canPublishAudio {
            flags.insert(.withAudio)
        }

        if !self.isAudioOnly, room.canPublishVideo {
            flags.insert(.withVideo)
        }

        return flags
    }

    init(delegate: NCCallControllerDelegate, room: NCRoom, account: TalkAccount, isAudioOnly: Bool, userSessionId: String, voiceChatMode: Bool) {
        self.delegate = delegate
        self.room = room
        self.account = account
        self.userSessionId = userSessionId
        self.isAudioOnly = isAudioOnly

        self.signalingController = NCSignalingController(for: room)

        super.init()

        self.signalingController.observer = self

        // NCCallController is only initialized after joining the room. At that point we ensured that there's
        // an external signaling controller set, in case we are using external signaling.
        self.externalSignalingController = NCSettingsController.sharedInstance().externalSignalingController(forAccountId: account.accountId)
        self.externalSignalingController?.delegate = self

        WebRTCCommon.shared.dispatch {
            if isAudioOnly || voiceChatMode {
                NCAudioController.shared.setAudioSessionToVoiceChatMode()
            } else {
                NCAudioController.shared.setAudioSessionToVideoChatMode()
            }
        }

        self.initRecorder()

        // Screensharing is done in an extension, therefore we need to listen to systemwide notifications#
        DarwinNotificationCenter.shared.addHandler(notificationName: DarwinNotificationCenter.broadcastStartedNotification, owner: self) {
            WebRTCCommon.shared.dispatch {
                self.startScreenshare()
            }
        }

        DarwinNotificationCenter.shared.addHandler(notificationName: DarwinNotificationCenter.broadcastStoppedNotification, owner: self) {
            WebRTCCommon.shared.dispatch {
                self.stopScreenshare()
            }
        }

        AllocationTracker.shared.addAllocation()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        DarwinNotificationCenter.shared.removeHandler(notificationName: DarwinNotificationCenter.broadcastStartedNotification, owner: self)
        DarwinNotificationCenter.shared.removeHandler(notificationName: DarwinNotificationCenter.broadcastStoppedNotification, owner: self)
        AllocationTracker.shared.removeAllocation()
        print("NCCallController dealloc")
    }

    public func startCall() {
        NCLog.log("Start call in NCCallController for token \(self.room.token)")

        // Make sure the signaling controller has retrieved the settings before joining a call
        self.signalingController.updateSignalingSettings { _ in
            let authStatus = AVCaptureDevice.authorizationStatus(for: .video)

            if !self.isAudioOnly, authStatus == .notDetermined {
                AVCaptureDevice.requestAccess(for: .video) { _ in
                    self.createLocalMedia()
                    self.joinCall()
                }
            } else {
                self.createLocalMedia()
                self.joinCall()
            }
        }
    }

    public func joinCall() {
        NCLog.log("Join call in NCCallController for token \(self.room.token)")

        self.joinCallTask = NCAPIController.shared.joinCall(inRoom: self.room.token, withCallFlags: self.joinCallFlags, joinSilently: self.silentCall, joinSilentlyFor: self.silentFor, withRecordingConsent: self.recordingConsent, forAccount: self.account, completionBlock: { error, statusCode in
            WebRTCCommon.shared.dispatch {
                if let error {
                    if error.underlyingError.code == NSURLErrorCancelled {
                        self.joinCallAttempts = 0
                        return
                    }

                    if self.joinCallAttempts < 3 {
                        NCLog.log("Could not join call in \(self.room.token), retrying. \(self.joinCallAttempts)")
                        self.joinCallAttempts += 1

                        if statusCode == 404 {
                            // The conversation was not correctly joined by us / our session expired
                            // Instead of joining again, try to reconnect to correctly join the conversation again
                            self.forceReconnect()
                        } else {
                            self.joinCall()
                        }

                        return
                    }

                    self.delegate?.callControllerDidFailedJoiningCall(self, statusCode: statusCode, errorReason: self.getJoinCallErrorReason(statusCode))
                    NCLog.log("Could not join call in \(self.room.token), StatusCode: \(statusCode), Error: \(error)")
                } else {
                    NCLog.log("Did join call in NCCallController for \(self.room.token)")

                    self.delegate?.callControllerDidJoinCall(self)
                    self.startMonitoringMicrophoneAudioLevel()

                    if let externalSignalingController = self.externalSignalingController {
                        if externalSignalingController.hasMCU {
                            self.createPublisherPeerConnection()
                        }
                    } else {
                        // Only with internal signaling we need to query the API for peers in call
                        self.getPeersForCall()
                        self.signalingController.startPullingSignalingMessages()
                    }

                    self.joinedCallOnce = true
                    self.joinCallAttempts = 0
                }
            }
        })
    }

    private func getJoinCallErrorReason(_ statusCode: Int) -> String {
        switch statusCode {
        case 0:
            return NSLocalizedString("No response from server", comment: "")
        case 400:
            return NSLocalizedString("Recording consent is required", comment: "")
        case 403:
            return NSLocalizedString("This conversation is read-only", comment: "")
        case 404:
            return NSLocalizedString("Conversation not found or not joined", comment: "")
        case 412:
            return NSLocalizedString("Lobby is still active and you're not a moderator", comment: "")
        default:
            return NSLocalizedString("Unknown error occurred", comment: "")
        }
    }

    public func shouldRejoinCall() {
        self.createLocalMedia()

        self.joinCallTask = NCAPIController.shared.joinCall(inRoom: self.room.token, withCallFlags: self.joinCallFlags, joinSilently: self.silentCall, joinSilentlyFor: self.silentFor, withRecordingConsent: self.recordingConsent, forAccount: self.account, completionBlock: { error, statusCode in
            WebRTCCommon.shared.dispatch {
                if let error {
                    if self.joinCallAttempts < 3 {
                        NCLog.log("Could not rejoin call, retrying. \(self.joinCallAttempts)")
                        self.joinCallAttempts += 1
                        self.shouldRejoinCall()

                        return
                    }

                    self.delegate?.callControllerDidFailedJoiningCall(self, statusCode: statusCode, errorReason: self.getJoinCallErrorReason(statusCode))
                    print("Could not rejoin call. Error \(error)")
                } else {
                    self.delegate?.callControllerDidJoinCall(self)
                    print("Rejoined call")

                    if self.externalSignalingController?.hasMCU == true {
                        self.createPublisherPeerConnection()
                    }

                    self.joinCallAttempts = 0
                }
            }
        })
    }

    public func willRejoinCall() {
        print("willRejoinCall")

        WebRTCCommon.shared.dispatch {
            self.userInCall = 0
            self.cleanCurrentPeerConnections()
            self.delegate?.callControllerIsReconnectingCall(self)
            self.preparedForRejoin = true
        }
    }

    public func willSwitchToCall(_ token: String) {
        print("willSwitchToCall")

        WebRTCCommon.shared.dispatch {
            let isAudioEnabled = self.isAudioEnabled()
            let isVideoEnabled = self.isVideoEnabled()

            self.stopCallController()

            self.leaveCallInServer(forAll: false) { error in
                if let error {
                    print("Could not leave call. Error: \(error)")
                }

                self.delegate?.callController(self, isSwitchingToCall: token, withAudioEnabled: isAudioEnabled, andVideoEnabled: isVideoEnabled)
            }
        }
    }

    public func forceReconnect() {
        NCLog.log("Force reconnect")

        WebRTCCommon.shared.dispatch {
            self.joinCallTask?.cancel()
            self.joinCallTask = nil

            self.userInCall = 0
            self.cleanCurrentPeerConnections()
            self.delegate?.callControllerIsReconnectingCall(self)

            // Remember current audio and video status before rejoin the call
            self.disableAudioAtStart = !self.isAudioEnabled()
            self.disableVideoAtStart = !self.isVideoEnabled()

            if self.externalSignalingController == nil {
                self.rejoinCallUsingInternalSignaling()
                return
            }

            self.externalSignalingController?.forceReconnectForRejoin()
        }
    }

    public func rejoinCallUsingInternalSignaling() {
        NCAPIController.shared.leaveCall(inRoom: self.room.token, forAllParticipants: false, forAccount: self.account) { error in
            if error == nil {
                self.shouldRejoinCallUsingInternalSignaling = true
            }
        }
    }

    public func stopCallController() {
        self.isLeavingCall = true
        self.stopSendingCurrentState()

        NotificationCenter.default.removeObserver(self)
        DarwinNotificationCenter.shared.removeHandler(notificationName: DarwinNotificationCenter.broadcastStartedNotification, owner: self)
        DarwinNotificationCenter.shared.removeHandler(notificationName: DarwinNotificationCenter.broadcastStoppedNotification, owner: self)

        self.externalSignalingController?.delegate = nil

        self.cameraController?.stopAVCaptureSession()
        self.stopSimulatorVideoCapturer()

        WebRTCCommon.shared.dispatch {
            self.stopScreenshare()
            self.cleanCurrentPeerConnections()
            self.localAudioTrack = nil
            self.localVideoTrack = nil
            self.connectionsDict = [:]
        }

        self.stopMonitoringMicrophoneAudioLevel()
        self.signalingController.stopAllRequests()

        self.getPeersForCallTask?.cancel()
        self.getPeersForCallTask = nil

        self.joinCallTask?.cancel()
        self.joinCallTask = nil
    }

    public func leaveCallInServer(forAll allParticipants: Bool, withCompletionBlock completionBlock: @escaping (_ error: OcsError?) -> Void) {
        if self.userInCall > 0 {
            NCAPIController.shared.leaveCall(inRoom: self.room.token, forAllParticipants: allParticipants, forAccount: self.account) { error in
                completionBlock(error)
            }
        } else {
            completionBlock(nil)
        }
    }

    public func leaveCall(forAll allParticipants: Bool) {
        self.stopCallController()

        self.leaveCallInServer(forAll: allParticipants) { error in
            if let error {
                print("Could not leave call. Error: \(error)")
            }

            self.delegate?.callControllerDidEndCall(self)
        }
    }

    public func isVideoEnabled() -> Bool {
        WebRTCCommon.shared.assertQueue()

        return self.localVideoTrack?.isEnabled ?? false
    }

    public func isAudioEnabled() -> Bool {
        WebRTCCommon.shared.assertQueue()

        return self.localAudioTrack?.isEnabled ?? false
    }

    public func getVideoEnabledState(withCompletionBlock completionBlock: @escaping (_ isEnabled: Bool) -> Void) {
        WebRTCCommon.shared.dispatch {
            completionBlock(self.isVideoEnabled())
        }
    }

    public func getAudioEnabledState(withCompletionBlock completionBlock: @escaping (_ isEnabled: Bool) -> Void) {
        WebRTCCommon.shared.dispatch {
            completionBlock(self.isAudioEnabled())
        }
    }

    public func switchCamera() {
        self.cameraController?.switchCamera()
    }

    public func enableVideo(_ enable: Bool) {
        WebRTCCommon.shared.dispatch {
            if enable {
                self.localVideoCaptureController?.startCapture()
            } else {
                self.localVideoCaptureController?.stopCapture()
            }

            self.localVideoTrack?.isEnabled = enable
            self.sendMessageToAll(ofType: enable ? "videoOn" : "videoOff", withPayload: nil)
        }
    }

    public func enableAudio(_ enable: Bool) {
        WebRTCCommon.shared.dispatch {
            self.localAudioTrack?.isEnabled = enable
            self.sendMessageToAll(ofType: enable ? "audioOn" : "audioOff", withPayload: nil)

            if !enable {
                self.speaking = false
                self.sendMessageToAll(ofType: "stoppedSpeaking", withPayload: nil)
            }
        }
    }

    public func isBackgroundBlurEnabled() -> Bool {
        return self.cameraController?.isBackgroundBlurEnabled() ?? false
    }

    public func enableBackgroundBlur(_ enable: Bool) {
        self.cameraController?.enableBackgroundBlur(enable: enable)
    }

    public func isCameraAccessAvailable() -> Bool {
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        return authStatus == .authorized
    }

    public func isMicrophoneAccessAvailable() -> Bool {
        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        return authStatus == .authorized
    }

    public func stopCapturing() {
        self.cameraController?.stopAVCaptureSession()
        self.stopSimulatorVideoCapturer()
    }

    public func raiseHand(_ raised: Bool) {
        WebRTCCommon.shared.dispatch {
            let timeStamp = Date().timeIntervalSince1970 * 1000

            let payload: [String: Any] = [
                "state": raised,
                "timestamp": String(format: "%.0f", timeStamp)
            ]

            for (_, peer) in self.connectionsDict {
                let message = NCRaiseHandMessage(from: self.signalingSessionId,
                                                 to: peer.peerId,
                                                 sid: peer.sid,
                                                 roomType: peer.roomType,
                                                 payload: payload)

                guard let message else { continue }

                if let externalSignalingController = self.externalSignalingController {
                    externalSignalingController.sendCallMessage(message)
                } else {
                    self.signalingController.send(message)
                }
            }
        }

        // Request or stop requesting assistance if we are in a breakout room and we are not moderators
        if !self.room.isBreakoutRoom || self.room.canModerate {
            return
        }

        Task {
            if raised {
                try? await NCAPIController.shared.requestAssistance(inRoom: self.room.token, forAccount: self.account)
            } else {
                try? await NCAPIController.shared.stopRequestingAssistance(inRoom: self.room.token, forAccount: self.account)
            }
        }
    }

    public func sendReaction(_ reaction: String) {
        WebRTCCommon.shared.dispatch {
            let payload = [
                "reaction": reaction
            ]

            for (_, peer) in self.connectionsDict {
                let message = NCReactionMessage(from: self.signalingSessionId,
                                                to: peer.peerId,
                                                sid: peer.sid,
                                                roomType: peer.roomType,
                                                payload: payload)

                guard let message else { continue }

                if let externalSignalingController = self.externalSignalingController {
                    externalSignalingController.sendCallMessage(message)
                } else {
                    self.signalingController.send(message)
                }
            }
        }
    }

    public func startRecording() {
        NCAPIController.shared.startRecording(inRoom: self.room.token, forAccount: self.account) { error in
            if let error {
                print("Could not start call recording. Error: \(error)")
            }
        }
    }

    public func stopRecording() {
        NCAPIController.shared.stopRecording(inRoom: self.room.token, forAccount: self.account) { error in
            if let error {
                print("Could not stop call recording. Error: \(error)")
            }
        }
    }

    public func startScreenshare() {
        WebRTCCommon.shared.assertQueue()

        guard !self.screensharingActive else { return }

        let peerConnectionFactory = WebRTCCommon.shared.peerConnectionFactory
        let videoSource = peerConnectionFactory.videoSource()
        let videoCapturer = RTCVideoCapturer(delegate: videoSource)

        self.screensharingController.startCapture(with: videoSource, with: videoCapturer)
        self.localScreenTrack = peerConnectionFactory.videoTrack(with: videoSource, trackId: NCCallController.kNCScreenTrackId)

        if let externalSignalingController, externalSignalingController.hasMCU {
            self.createScreenPublisherPeerConnection()
        } else {
            for session in sessionsInCall where session != self.signalingSessionId {
                self.sendScreensharingOffer(toSessionId: session)
            }
        }

        self.screensharingActive = true
        self.delegate?.callControllerDidChangeScreenrecording(self)
    }

    private func sendScreensharingOffer(toSessionId sessionId: String) {
        let peerConnectionWrapper = self.getOrCreatePeerConnectionWrapper(forSessionId: sessionId, withSid: nil, ofType: kRoomTypeScreen, forOwnScreenshare: true)
        peerConnectionWrapper.sendPublisherOffer()
    }

    public func stopScreenshare() {
        WebRTCCommon.shared.assertQueue()

        self.screensharingController.stopCapture()

        if let externalSignalingController {
            // Close screen publisher peer connection
            self.screenPublisherPeerConnection?.close()
            self.screenPublisherPeerConnection = nil

            let peerKey = self.getPeerKey(withSessionId: self.signalingSessionId, ofType: kRoomTypeScreen, forOwnScreenshare: true)
            self.connectionsDict.removeValue(forKey: peerKey)

            // Send unshare screen signaling message to all the other peers
            externalSignalingController.sendRoomMessage(ofType: "unshareScreen", andRoomType: kRoomTypeScreen)
        } else {
            for (_, peer) in self.connectionsDict {
                if peer.isOwnScreensharePeer {
                    // Close all own screen peer connections
                    self.cleanPeerConnection(forSessionId: peer.peerId, ofType: kRoomTypeScreen, forOwnScreenshare: true)
                } else {
                    // Send unshare screen signaling message to all the other peers
                    let message = NCUnshareScreenMessage(from: self.signalingSessionId,
                                                         to: peer.peerId,
                                                         sid: peer.sid,
                                                         roomType: peer.roomType,
                                                         payload: [:])

                    self.signalingController.send(message)
                }
            }
        }

        self.screensharingActive = false
        self.delegate?.callControllerDidChangeScreenrecording(self)
    }

    // MARK: - Call controller

    private func cleanCurrentPeerConnections() {
        WebRTCCommon.shared.assertQueue()

        for (_, peerConnectionWrapper) in self.connectionsDict {
            if !peerConnectionWrapper.isMCUPublisherPeer {
                if peerConnectionWrapper.roomType == kRoomTypeVideo {
                    self.delegate?.callController(self, peerLeft: peerConnectionWrapper)
                } else if peerConnectionWrapper.roomType == kRoomTypeScreen {
                    self.delegate?.callController(self, didReceiveUnshareScreenFromPeer: peerConnectionWrapper)
                }
            }

            peerConnectionWrapper.delegate = nil
            peerConnectionWrapper.close()
        }

        for (_, pendingOfferTimer) in self.pendingOffersDict {
            pendingOfferTimer.invalidate()
        }

        self.connectionsDict = [:]
        self.pendingOffersDict = [:]
        self.usersInRoom = []
        self.sessionsInCall = []
        self.publisherPeerConnection = nil
        self.screenPublisherPeerConnection = nil
    }

    private func cleanPeerConnection(forSessionId sessionId: String, ofType roomType: String, forOwnScreenshare ownScreenshare: Bool) {
        WebRTCCommon.shared.assertQueue()

        let peerKey = self.getPeerKey(withSessionId: sessionId, ofType: roomType, forOwnScreenshare: ownScreenshare)

        if let removedPeerConnection = connectionsDict[peerKey] {
            if roomType == kRoomTypeVideo {
                print("Removing peer from call: \(sessionId)")
                self.delegate?.callController(self, peerLeft: removedPeerConnection)
            } else if roomType == kRoomTypeScreen, !ownScreenshare {
                print("Removing screensharing from peer: \(sessionId)")
                self.delegate?.callController(self, didReceiveUnshareScreenFromPeer: removedPeerConnection)
            }

            removedPeerConnection.delegate = nil
            removedPeerConnection.close()

            connectionsDict.removeValue(forKey: peerKey)
        }
    }

    private func cleanAllPeerConnections(forSessionId sessionId: String) {
        WebRTCCommon.shared.assertQueue()

        self.cleanPeerConnection(forSessionId: sessionId, ofType: kRoomTypeVideo, forOwnScreenshare: false)
        self.cleanPeerConnection(forSessionId: sessionId, ofType: kRoomTypeScreen, forOwnScreenshare: false)

        // Invalidate possible request timers
        let peerVideoKey = self.getPeerKey(withSessionId: sessionId, ofType: kRoomTypeVideo, forOwnScreenshare: false)
        if let pendingVideoRequestTimer = pendingOffersDict[peerVideoKey] {
            DispatchQueue.main.async {
                pendingVideoRequestTimer.invalidate()
            }
        }

        let peerScreenKey = self.getPeerKey(withSessionId: sessionId, ofType: kRoomTypeScreen, forOwnScreenshare: false)
        if let pendingScreenRequestTimer = pendingOffersDict[peerScreenKey] {
            DispatchQueue.main.async {
                pendingScreenRequestTimer.invalidate()
            }
        }
    }

    // MARK: - Microphone audio level

    private func startMonitoringMicrophoneAudioLevel() {
        DispatchQueue.main.async {
            self.micAudioLevelTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(self.checkMicAudioLevel), userInfo: nil, repeats: true)
        }
    }

    private func stopMonitoringMicrophoneAudioLevel() {
        DispatchQueue.main.async {
            self.micAudioLevelTimer?.invalidate()
            self.micAudioLevelTimer = nil
            self.recorder?.stop()
            self.recorder = nil
        }
    }

    private func initRecorder() {
        let url = URL(filePath: "/dev/null")

        let settings: [String: Any] = [
            AVSampleRateKey: 44100.0 as NSNumber,
            AVFormatIDKey: kAudioFormatAppleLossless as NSNumber,
            AVNumberOfChannelsKey: 0 as NSNumber,
            AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue as NSNumber
        ]

        if let recorder = try? AVAudioRecorder(url: url, settings: settings) {
            self.recorder = recorder
            recorder.prepareToRecord()
            recorder.isMeteringEnabled = true
            recorder.record()
        } else {
            print("Failed initializing recorder.")
        }
    }

    @objc
    private func checkMicAudioLevel() {
        WebRTCCommon.shared.dispatch {
            guard self.isAudioEnabled(), let recorder = self.recorder else { return }

            recorder.updateMeters()
            let averagePower = recorder.averagePower(forChannel: 0)

            if averagePower >= -50.0, !self.speaking {
                self.speaking = true
                self.sendMessageToAll(ofType: "speaking", withPayload: nil)
            } else if averagePower < -50.0, self.speaking {
                self.speaking = false
                self.sendMessageToAll(ofType: "stoppedSpeaking", withPayload: nil)
            }
        }
    }

    // MARK: - Call participants (internal signaling)

    private func getPeersForCall() {
        self.getPeersForCallTask = NCAPIController.shared.getPeersForCall(inRoom: self.room.token, forAccount: self.account, completionBlock: { peers, error, _ in
            guard let peers, error == nil else { return }

            WebRTCCommon.shared.dispatch {
                self.peersInCall = peers
            }
        })
    }

    // MARK: - Audio & Video senders

    private func createLocalAudioTrack() {
        WebRTCCommon.shared.assertQueue()

        let peerConnectionFactory = WebRTCCommon.shared.peerConnectionFactory
        let source = peerConnectionFactory.audioSource(with: nil)
        self.localAudioTrack = peerConnectionFactory.audioTrack(with: source, trackId: NCCallController.kNCAudioTrackId)
        self.localAudioTrack?.isEnabled = !self.disableAudioAtStart

        if CallKitManager.isCallKitAvailable() {
            CallKitManager.sharedInstance().changeAudioMuted(self.disableAudioAtStart, forCall: self.room.token)
        }

        self.delegate?.callController(self, didCreateLocalAudioTrack: self.localAudioTrack)
    }

    private func createLocalVideoTrack() {
        WebRTCCommon.shared.assertQueue()

        let peerConnectionFactory = WebRTCCommon.shared.peerConnectionFactory
        let videoSource = peerConnectionFactory.videoSource()

        #if targetEnvironment(simulator)
        // There's no camera on the simulator, so publish a generated test pattern instead
        let videoCapturer = SimulatorVideoCapturer(delegate: videoSource)
        videoCapturer.startCapture()
        self.simulatorVideoCapturer = videoCapturer

        self.localVideoTrack = peerConnectionFactory.videoTrack(with: videoSource, trackId: NCCallController.kNCVideoTrackId)
        self.localVideoTrack?.isEnabled = !self.disableVideoAtStart

        self.delegate?.callController(self, didCreateLocalVideoTrack: self.localVideoTrack)
        #else
        let videoCapturer = RTCVideoCapturer(delegate: videoSource)

        self.localVideoTrack = peerConnectionFactory.videoTrack(with: videoSource, trackId: NCCallController.kNCVideoTrackId)
        self.localVideoTrack?.isEnabled = !self.disableVideoAtStart

        self.delegate?.callController(self, didCreateLocalVideoTrack: self.localVideoTrack)

        let newCameraController = NCCameraController(videoSource: videoSource, videoCapturer: videoCapturer)
        newCameraController.delegate = self
        self.cameraController = newCameraController

        self.delegate?.callController(self, didCreateCameraController: newCameraController)
        #endif
    }

    private func stopSimulatorVideoCapturer() {
        #if targetEnvironment(simulator)
        self.simulatorVideoCapturer?.stopCapture()
        self.simulatorVideoCapturer = nil
        #endif
    }

    private func createLocalMedia() {
        self.cameraController?.stopAVCaptureSession()
        self.stopSimulatorVideoCapturer()

        WebRTCCommon.shared.dispatch {
            self.localAudioTrack = nil
            self.localVideoTrack = nil

            if self.room.canPublishAudio, self.isMicrophoneAccessAvailable() {
                self.createLocalAudioTrack()
            } else {
                self.delegate?.callController(self, didCreateLocalAudioTrack: nil)
            }

            if !self.isAudioOnly, self.room.canPublishVideo, self.isCameraAccessAvailable() {
                self.createLocalVideoTrack()
            } else {
                self.delegate?.callController(self, didCreateLocalVideoTrack: nil)
            }
        }
    }

    // MARK: - Peer Connection Wrapper

    private func getPeerKey(withSessionId sessionId: String, ofType roomType: String, forOwnScreenshare ownScreenshare: Bool = false) -> String {
        var peerKey = "\(sessionId)\(roomType)"

        if ownScreenshare {
            // If this is our own screensharing peer, we add "own" to the key, to distinguish our peer
            // to a receiving peer in case we are using internal signaling
            peerKey = "\(peerKey)own"
        }

        return peerKey
    }

    // TODO: Optional return?
    private func getPeerConnectionWrapper(forSessionId sessionId: String, ofType roomType: String, forOwnScreenshare ownScreenshare: Bool = false) -> NCPeerConnection? {
        WebRTCCommon.shared.assertQueue()

        let peerKey = self.getPeerKey(withSessionId: sessionId, ofType: roomType, forOwnScreenshare: ownScreenshare)

        return self.connectionsDict[peerKey]
    }

    private func getOrCreatePeerConnectionWrapper(forSessionId sessionId: String, withSid sid: String? = nil, ofType roomType: String, forOwnScreenshare ownScreenshare: Bool = false) -> NCPeerConnection {
        WebRTCCommon.shared.assertQueue()

        let peerKey = self.getPeerKey(withSessionId: sessionId, ofType: roomType, forOwnScreenshare: ownScreenshare)
        var peerConnectionWrapper = self.getPeerConnectionWrapper(forSessionId: sessionId, ofType: roomType, forOwnScreenshare: ownScreenshare)

        // When using internal signaling, if you and another participant are sharing the screen and you receive a candidate message
        // we can not know whether the message is for the sending or the received screen share only from the "from" field and the type.
        // We need to use the "sid"
        let screensharingPeer = (roomType == kRoomTypeScreen)
        if screensharingPeer {
            // We check if the signaling message was send to our own screen peer.
            // If the "sid" doesn't match, we have grabbed the correct peer connection above (if it existed)
            if let ownScreenPeerConnectionWrapper = self.getPeerConnectionWrapper(forSessionId: sessionId, ofType: roomType, forOwnScreenshare: true) {
                if ownScreenPeerConnectionWrapper.sid == sid {
                    peerConnectionWrapper = ownScreenPeerConnectionWrapper
                }
            }
        }

        if let peerConnectionWrapper {
            return peerConnectionWrapper
        }

        // Create a peer connection
        print("Creating a peer for \(sessionId)")
        let iceServers = self.signalingController.getIceServers()
        peerConnectionWrapper = NCPeerConnection(sessionId: sessionId, sid: sid, andICEServers: iceServers, forAudioOnlyCall: screensharingPeer ? false : self.isAudioOnly)
        peerConnectionWrapper?.roomType = roomType
        peerConnectionWrapper?.delegate = self
        peerConnectionWrapper?.isOwnScreensharePeer = ownScreenshare

        // Try to get displayName early
        if let actor = self.getActor(fromSessionId: sessionId), !actor.rawDisplayName.isEmpty {
            peerConnectionWrapper?.peerName = actor.displayName
        }

        // Do not add local stream when using a MCU or to screensharing peers
        if self.externalSignalingController == nil || self.externalSignalingController?.hasMCU == false {
            let peerConnection = peerConnectionWrapper?.getPeerConnection()

            if !screensharingPeer {
                if let localAudioTrack {
                    peerConnection?.add(localAudioTrack, streamIds: [NCCallController.kNCMediaStreamId])
                }

                if let localVideoTrack {
                    peerConnection?.add(localVideoTrack, streamIds: [NCCallController.kNCMediaStreamId])
                }
            } else if let localScreenTrack {
                peerConnection?.add(localScreenTrack, streamIds: [NCCallController.kNCMediaStreamId])
            }
        }

        // Add peer connection to the connections dictionary
        self.connectionsDict[peerKey] = peerConnectionWrapper

        // Notify about the new peer
        if !screensharingPeer {
            self.delegate?.callController(self, peerJoined: peerConnectionWrapper!)
        }

        return peerConnectionWrapper!
    }

    // MARK: - Peer Connection Wrapper

    private func sendMessageToAll(ofType type: String, withPayload payload: Any?) {
        WebRTCCommon.shared.assertQueue()

        if let externalSignalingController, externalSignalingController.hasMCU {
            self.publisherPeerConnection?.sendDataChannelMessage(ofType: type, withPayload: payload)
        } else {
            for (_, peerConnectionWrapper) in self.connectionsDict {
                peerConnectionWrapper.sendDataChannelMessage(ofType: type, withPayload: payload)
            }
        }

        // Send a signaling message only if we are using an external signaling server
        guard let externalSignalingController else { return }

        for (_, peer) in self.connectionsDict {
            var message: NCSignalingMessage?
            let from = self.signalingSessionId

            if type == "audioOn" {
                message = NCUnmuteMessage(from: from, to: peer.peerId, sid: peer.sid, roomType: peer.roomType, payload: ["name": "audio"])
            } else if type == "audioOff" {
                message = NCMuteMessage(from: from, to: peer.peerId, sid: peer.sid, roomType: peer.roomType, payload: ["name": "audio"])
            } else if type == "videoOn" {
                message = NCUnmuteMessage(from: from, to: peer.peerId, sid: peer.sid, roomType: peer.roomType, payload: ["name": "video"])
            } else if type == "videoOff" {
                message = NCMuteMessage(from: from, to: peer.peerId, sid: peer.sid, roomType: peer.roomType, payload: ["name": "video"])
            } else if type == "nickChanged" {
                let payload = ["name": self.account.userDisplayName]
                message = NCNickChangedMessage(from: from, to: peer.peerId, sid: peer.sid, roomType: peer.roomType, payload: payload)
            }

            if let message {
                externalSignalingController.sendCallMessage(message)
            }
        }
    }

    // MARK: - External signaling support

    private func createPublisherPeerConnection() {
        WebRTCCommon.shared.assertQueue()

        if self.publisherPeerConnection != nil || (self.localAudioTrack == nil && self.localVideoTrack == nil) {
            print("Not creating publisher peer connection. Already created or no local media.")
            return
        }

        NCLog.log("Creating publisher peer connection with sessionId: \(self.signalingSessionId)")

        let iceServers = self.signalingController.getIceServers()

        guard let peerConnectionWrapper = NCPeerConnection(forPublisherWithSessionId: self.signalingSessionId, andICEServers: iceServers, forAudioOnlyCall: true),
              let peerConnection = peerConnectionWrapper.getPeerConnection()
        else { return }

        peerConnectionWrapper.roomType = kRoomTypeVideo
        peerConnectionWrapper.delegate = self

        self.publisherPeerConnection = peerConnectionWrapper

        let peerKey = self.getPeerKey(withSessionId: self.signalingSessionId, ofType: kRoomTypeVideo, forOwnScreenshare: false)
        self.connectionsDict[peerKey] = peerConnectionWrapper

        if let localAudioTrack {
            peerConnection.add(localAudioTrack, streamIds: [NCCallController.kNCMediaStreamId])
        }

        if let localVideoTrack {
            peerConnection.add(localVideoTrack, streamIds: [NCCallController.kNCMediaStreamId])
        }

        peerConnectionWrapper.sendPublisherOffer()
    }

    private func createScreenPublisherPeerConnection() {
        WebRTCCommon.shared.assertQueue()

        if self.screenPublisherPeerConnection != nil || self.localScreenTrack == nil {
            print("Not creating publisher peer connection. Already created or no local media.")
            return
        }

        print("Creating publisher peer connection with sessionId: \(self.signalingSessionId)")

        let iceServers = self.signalingController.getIceServers()
        guard let peerConnectionWrapper = NCPeerConnection(forPublisherWithSessionId: self.signalingSessionId, andICEServers: iceServers, forAudioOnlyCall: true)
        else { return }

        peerConnectionWrapper.roomType = kRoomTypeScreen
        peerConnectionWrapper.isOwnScreensharePeer = true
        peerConnectionWrapper.delegate = self

        self.screenPublisherPeerConnection = peerConnectionWrapper

        let peerKey = self.getPeerKey(withSessionId: self.signalingSessionId, ofType: kRoomTypeScreen, forOwnScreenshare: true)
        self.connectionsDict[peerKey] = peerConnectionWrapper

        if let localScreenTrack, let peerConnection = peerConnectionWrapper.getPeerConnection() {
            peerConnection.add(localScreenTrack, streamIds: [NCCallController.kNCMediaStreamId])
        }

        peerConnectionWrapper.sendPublisherOffer()
    }

    public func requestOfferWithRepetition(forSessionId sessionId: String, withRoomType roomType: String) {
        WebRTCCommon.shared.assertQueue()

        let timeout = Int(Date().timeIntervalSince1970 + 60)
        let userInfo: [String: Any] = [
            "sessionId": sessionId,
            "roomType": roomType,
            "timeout": timeout
        ]

        let pendingOfferTimer = Timer(timeInterval: 8.0, target: self, selector: #selector(self.requestNewOffer), userInfo: userInfo, repeats: true)
        let peerKey = self.getPeerKey(withSessionId: sessionId, ofType: roomType, forOwnScreenshare: false)

        self.pendingOffersDict[peerKey] = pendingOfferTimer

        // Request new offer
        if let externalSignalingController {
            externalSignalingController.requestOffer(forSessionId: sessionId, andRoomType: roomType)
        }

        DispatchQueue.main.async {
            RunLoop.main.add(pendingOfferTimer, forMode: .default)
        }
    }

    @objc private func requestNewOffer(_ timer: Timer) {
        guard let userInfo = timer.userInfo as? [String: Any],
              let sessionId = userInfo["sessionId"] as? String,
              let roomType = userInfo["roomType"] as? String,
              let timeout = userInfo["timeout"] as? Int,
              let externalSignalingController
        else { return }

        WebRTCCommon.shared.dispatch {
            if Int(Date().timeIntervalSince1970) < timeout {
                print("Re-requesting an offer to session \(sessionId)")
                externalSignalingController.requestOffer(forSessionId: sessionId, andRoomType: roomType)
            } else {
                DispatchQueue.main.async {
                    timer.invalidate()
                }
            }
        }
    }

    private func checkIfPendingOffer(_ signalingMessage: NCSignalingMessage) {
        guard signalingMessage.messageType() == .offer else { return }

        let peerKey = self.getPeerKey(withSessionId: signalingMessage.from, ofType: signalingMessage.roomType, forOwnScreenshare: false)

        if let pendingRequestTimer = pendingOffersDict[peerKey] {
            print("Pending requested offer arrived. Removing timer.")

            DispatchQueue.main.async {
                pendingRequestTimer.invalidate()
            }
        }
    }

    // MARK: - Nick & Media info

    private func sendNick() {
        let payload = [
            "userid": self.account.userId,
            "name": self.account.userDisplayName
        ]

        WebRTCCommon.shared.dispatch {
            self.sendMessageToAll(ofType: "nickChanged", withPayload: payload)
        }
    }

    private func sendMediaState() {
        WebRTCCommon.shared.dispatch {
            // Send current audio state
            if self.isAudioEnabled() {
                print("Send audioOn to all")
                self.sendMessageToAll(ofType: "audioOn", withPayload: nil)
            } else {
                print("Send audioOff to all")
                self.sendMessageToAll(ofType: "audioOff", withPayload: nil)
            }

            // Send current video state
            if self.isVideoEnabled() {
                print("Send videoOn to all")
                self.sendMessageToAll(ofType: "videoOn", withPayload: nil)
            } else {
                print("Send videoOff to all")
                self.sendMessageToAll(ofType: "videoOff", withPayload: nil)
            }
        }
    }

    private func startSendingCurrentState() {
        DispatchQueue.main.async {
            guard !self.isLeavingCall else { return }

            self.sendCurrentStateTimer?.invalidate()
            self.sendCurrentStateTimer = nil

            self.sendCurrentState(withTimer: nil)
        }
    }

    private func stopSendingCurrentState() {
        DispatchQueue.main.async {
            self.sendCurrentStateTimer?.invalidate()
            self.sendCurrentStateTimer = nil
        }
    }

    @objc private func sendCurrentState(withTimer timer: Timer?) {
        var interval = 0

        if let userInfo = timer?.userInfo as? [String: Any], let timerInterval = userInfo["interval"] as? Int {
            interval = timerInterval
        }

        DispatchQueue.main.async {
            // Don't send or re-arm the timer once we are leaving the call, otherwise an in-flight
            // execution could keep broadcasting our state after the call ended.
            guard !self.isLeavingCall else { return }

            self.sendNick()
            self.sendMediaState()

            if interval == 0 {
                interval = 1
            } else {
                interval *= 2
            }

            if interval > 16 {
                return
            }

            let userInfo = ["interval": interval]
            self.sendCurrentStateTimer = Timer.scheduledTimer(timeInterval: TimeInterval(interval), target: self, selector: #selector(self.sendCurrentState(withTimer:)), userInfo: userInfo, repeats: false)
        }
    }

    // MARK: - Control support

    public func forceMuteOthers() {
        WebRTCCommon.shared.dispatch {
            for (_, peer) in self.connectionsDict {
                let payload = [
                    "action": "forceMute",
                    "peerId": peer.peerId
                ]

                let message = NCControlMessage(from: self.signalingSessionId,
                                               to: peer.peerId,
                                               sid: peer.sid,
                                               roomType: peer.roomType,
                                               payload: payload)

                guard let message else { continue }

                if let externalSignalingController = self.externalSignalingController {
                    externalSignalingController.sendCallMessage(message)
                } else {
                    self.signalingController.send(message)
                }
            }
        }
    }

    // MARK: - External signaling controller delegate

    func externalSignalingController(_ externalSignalingController: NCExternalSignalingController, didReceivedSignalingMessage signalingMessageDict: [AnyHashable: Any]) {
        guard let signalingMessage = NCSignalingMessage.messageFromExternalSignalingJSONDictionary(signalingMessageDict)
        else { return }

        WebRTCCommon.shared.dispatch {
            self.checkIfPendingOffer(signalingMessage)
            self.processSignalingMessage(signalingMessage)
        }
    }

    func externalSignalingController(_ externalSignalingController: NCExternalSignalingController, didReceivedParticipantListMessage participantListMessageDict: [AnyHashable: Any]) {
        WebRTCCommon.shared.dispatch {
            var usersInRoom = participantListMessageDict["users"] as? [[String: Any]] ?? []

            // Update for "all" participants
            if participantListMessageDict[boolForKey: "all"] == true {
                // Check if "incall" key exists
                if let incall = participantListMessageDict[boolForKey: "incall"], !incall {
                    // Clear usersInRoom array if incall == false
                    usersInRoom = []
                }
            }

            self.processUsersInRoom(usersInRoom)
        }
    }

    func externalSignalingControllerShouldRejoinCall(_ externalSignalingController: NCExternalSignalingController) {
        // Call controller should rejoin the call if it was notifiy with the willRejoin notification first.
        // Also we should check that it has joined the call first with the startCall method.

        WebRTCCommon.shared.dispatch {
            guard self.preparedForRejoin else { return }

            self.preparedForRejoin = false

            if self.joinedCallOnce {
                self.shouldRejoinCall()
            } else {
                self.joinCall()
            }
        }
    }

    func externalSignalingControllerWillRejoinCall(_ externalSignalingController: NCExternalSignalingController) {
        WebRTCCommon.shared.dispatch {
            self.willRejoinCall()
        }
    }

    func externalSignalingController(_ externalSignalingController: NCExternalSignalingController, shouldSwitchToCall roomToken: String) {
        self.willSwitchToCall(roomToken)
    }

    // MARK: - Signaling controller delegate

    func signalingController(_ signalingController: NCSignalingController!, didReceiveSignalingMessage message: [AnyHashable: Any]!) {
        WebRTCCommon.shared.dispatch {
            guard !self.isLeavingCall, let messageType = message["type"] as? String else { return }

            if messageType == "usersInRoom" {
                if let usersInRoom = message["data"] as? [[String: Any]] {
                    self.processUsersInRoom(usersInRoom)
                }
            } else if messageType == "message" {
                if let jsonData = message["data"] as? String {
                    if let signalingMessage = NCSignalingMessage.messageFromJSONString(jsonData) {
                        self.processSignalingMessage(signalingMessage)
                    }
                }
            } else {
                print("Unknown message: \(message["data"])")
            }
        }
    }

    // MARK: - NCCameraController delegate

    func didDrawFirstFrameOnLocalView() {
        self.delegate?.callControllerDidDrawFirstLocalFrame(self)
    }

    // MARK: - NCPeerConnection delegate
    // Delegates from NCPeerConnection are already dispatched to the webrtc worker queue

    func peerConnection(_ peerConnection: NCPeerConnection!, didAdd stream: RTCMediaStream!) {
        guard !peerConnection.isMCUPublisherPeer else { return }

        self.delegate?.callController(self, didAddStream: stream, ofPeer: peerConnection)
    }

    func peerConnection(_ peerConnection: NCPeerConnection!, didRemove stream: RTCMediaStream!) {
        guard !peerConnection.isMCUPublisherPeer else { return }

        self.delegate?.callController(self, didRemoveStream: stream, ofPeer: peerConnection)
    }

    func peerConnection(_ peerConnection: NCPeerConnection!, didChange newState: RTCIceConnectionState) {
        if newState == .failed {
            if peerConnection.roomType == kRoomTypeScreen {
                self.stopScreenshare()
                return
            }

            if peerConnection.isMCUPublisherPeer {
                // If publisher peer failed, then reconnect
                NCLog.log("Publisher peer connection failed")
                self.forceReconnect()
            } else if let externalSignalingController, externalSignalingController.hasMCU {
                // If another peer failed using MCU, then request a new offer
                let sessionId = peerConnection.peerId
                if let roomType = peerConnection.roomType {
                    // Close failed peer connection
                    self.cleanPeerConnection(forSessionId: sessionId, ofType: roomType, forOwnScreenshare: false)

                    // Request new offer
                    self.requestOfferWithRepetition(forSessionId: sessionId, withRoomType: roomType)
                }
            }
        }

        if newState == .connected {
            self.startSendingCurrentState()

            if let externalSignalingController {
                if peerConnection.isMCUPublisherPeer {
                    NCLog.log("Publisher peer changed to connected")
                }

                if self.screensharingActive {
                    if peerConnection.isMCUPublisherPeer {
                        // This is our screensharing publisher peer which connected just now, so ask everyone to request our peer now
                        for (_, peer) in self.connectionsDict {
                            guard peer.peerId != self.screenPublisherPeerConnection?.peerId
                            else { continue }

                            externalSignalingController.sendSendOfferMessage(withSessionId: peer.peerId, andRoomType: kRoomTypeScreen)
                        }
                    } else {
                        // Another new peer joined, tell the peer that we are screensharing and it needs to request the screen peer
                        externalSignalingController.sendSendOfferMessage(withSessionId: peerConnection.peerId, andRoomType: kRoomTypeScreen)
                    }
                }
            }
        }

        if !peerConnection.isMCUPublisherPeer {
            self.delegate?.callController(self, iceStatusChanged: newState, ofPeer: peerConnection)
        }
    }

    func peerConnection(_ peerConnection: NCPeerConnection!, didGenerate candidate: RTCIceCandidate!) {
        let message = NCICECandidateMessage(candidate: candidate,
                                            from: self.signalingSessionId,
                                            to: peerConnection.peerId,
                                            sid: peerConnection.sid,
                                            roomType: peerConnection.roomType,
                                            broadcaster: peerConnection.isOwnScreensharePeer ? self.signalingSessionId : nil)

        guard let message else { return }

        if let externalSignalingController {
            externalSignalingController.sendCallMessage(message)
        } else {
            signalingController.send(message)
        }
    }

    func peerConnection(_ peerConnection: NCPeerConnection!, needsToSend sessionDescription: RTCSessionDescription!) {
        let message = NCSessionDescriptionMessage(sessionDescription: sessionDescription,
                                                  from: self.signalingSessionId,
                                                  to: peerConnection.peerId,
                                                  sid: peerConnection.sid,
                                                  roomType: peerConnection.roomType,
                                                  broadcaster: peerConnection.isOwnScreensharePeer ? self.signalingSessionId : nil,
                                                  nick: self.account.userDisplayName)

        guard let message else { return }

        if let externalSignalingController {
            externalSignalingController.sendCallMessage(message)
        } else {
            signalingController.send(message)
        }
    }

    func peerConnection(_ peerConnection: NCPeerConnection!, didReceiveStatusDataChannelMessage type: String!) {
        self.delegate?.callController(self, didReceiveDataChannelMessage: type, fromPeer: peerConnection)
    }

    func peerConnection(_ peerConnection: NCPeerConnection!, didReceivePeerNick nick: String!) {
        self.delegate?.callController(self, didReceiveNick: nick, fromPeer: peerConnection)
    }

    // MARK: - Signaling functions

    private func processSignalingMessage(_ signalingMessage: NCSignalingMessage?) {
        guard let signalingMessage else { return }

        WebRTCCommon.shared.assertQueue()

        switch signalingMessage.messageType() {
        case .offer, .answer:
            self.processOfferAnswer(signalingMessage)

        case .candidate:
            self.processCandidate(signalingMessage)

        case .unshareScreen:
            self.processUnshareScreen(signalingMessage)

        case .control:
            self.processControl(signalingMessage)

        case .mute, .unmute:
            self.processMuteUnmute(signalingMessage)

        case .nickChanged:
            self.processNickChanged(signalingMessage)

        case .raiseHand:
            self.processRaiseHand(signalingMessage)

        case .recording:
            self.processRecording(signalingMessage)

        case .reaction:
            self.processReaction(signalingMessage)

        default:
            print("Received an unknown signaling message: \(signalingMessage)")
        }
    }

    private func processOfferAnswer(_ signalingMessage: NCSignalingMessage) {
        // If we receive an answer to a "screen" type, it can only be our own publishing peer
        let isAnswerToOwnScreenshare = signalingMessage.messageType() == .answer && signalingMessage.roomType == kRoomTypeScreen

        // If there is already a peer connection but a new offer is received with a different sid the existing
        // peer connection is stale, so it needs to be removed and a new one created instead.
        var peerConnectionWrapper = self.getPeerConnectionWrapper(forSessionId: signalingMessage.from, ofType: signalingMessage.roomType, forOwnScreenshare: isAnswerToOwnScreenshare)
        var peerName: String?

        if signalingMessage.messageType() == .offer, let peerConnectionWrapper,
           let sid = signalingMessage.sid, !sid.isEmpty, sid != peerConnectionWrapper.sid {

            // Remember the peerName for the new connectionWrapper
            peerName = peerConnectionWrapper.peerName
            self.cleanPeerConnection(forSessionId: signalingMessage.from, ofType: signalingMessage.roomType, forOwnScreenshare: isAnswerToOwnScreenshare)
        }

        peerConnectionWrapper = self.getOrCreatePeerConnectionWrapper(forSessionId: signalingMessage.from, withSid: signalingMessage.sid, ofType: signalingMessage.roomType, forOwnScreenshare: isAnswerToOwnScreenshare)
        if let peerConnectionWrapper, let sdpMessage = signalingMessage as? NCSessionDescriptionMessage {
            let sessionDescription = sdpMessage.sessionDescription
            peerConnectionWrapper.setRemoteDescription(sessionDescription)

            if let nick = sdpMessage.nick, !nick.isEmpty {
                peerConnectionWrapper.peerName = nick
            } else if let peerName {
                peerConnectionWrapper.peerName = peerName
            }
        }
    }

    private func processCandidate(_ signalingMessage: NCSignalingMessage) {
        let peerConnectionWrapper = self.getOrCreatePeerConnectionWrapper(forSessionId: signalingMessage.from, withSid: signalingMessage.sid, ofType: signalingMessage.roomType)
        if let candidateMessage = signalingMessage as? NCICECandidateMessage {
            peerConnectionWrapper.add(candidateMessage.candidate)
        }
    }

    private func processUnshareScreen(_ signalingMessage: NCSignalingMessage) {
        guard let peerConnectionWrapper = self.getPeerConnectionWrapper(forSessionId: signalingMessage.from, ofType: signalingMessage.roomType)
        else { return }

        let peerKey = self.getPeerKey(withSessionId: signalingMessage.from, ofType: kRoomTypeScreen, forOwnScreenshare: false)

        if let screensharePeer = self.connectionsDict[peerKey] {
            screensharePeer.close()
            self.connectionsDict.removeValue(forKey: peerKey)
        }

        self.delegate?.callController(self, didReceiveUnshareScreenFromPeer: peerConnectionWrapper)
    }

    private func processControl(_ signalingMessage: NCSignalingMessage) {
        if let action = signalingMessage.payload["action"] as? String, action == "forceMute",
           let peerId = signalingMessage.payload["peerId"] as? String {

            self.delegate?.callController(self, didReceiveForceMuteActionForPeerId: peerId)
        }
    }

    private func processMuteUnmute(_ signalingMessage: NCSignalingMessage) {
        guard let peerConnectionWrapper = self.getPeerConnectionWrapper(forSessionId: signalingMessage.from, ofType: signalingMessage.roomType),
              let name = signalingMessage.payload["name"] as? String
        else { return }

        if name == "audio" {
            let messageType = signalingMessage.messageType() == .mute ? "audioOff" : "audioOn"
            peerConnectionWrapper.sendDataChannelMessage(ofType: messageType, withPayload: nil)
        } else if name == "video" {
            let messageType = signalingMessage.messageType() == .mute ? "videoOff" : "videoOn"
            peerConnectionWrapper.sendDataChannelMessage(ofType: messageType, withPayload: nil)
        }
    }

    private func processNickChanged(_ signalingMessage: NCSignalingMessage) {
        guard let peerConnectionWrapper = self.getPeerConnectionWrapper(forSessionId: signalingMessage.from, ofType: signalingMessage.roomType),
              let name = signalingMessage.payload["name"] as? String
        else { return }

        if !name.isEmpty {
            peerConnectionWrapper.setStatusForDataChannelMessageType("nickChanged", withPayload: name)
        }
    }

    private func processRaiseHand(_ signalingMessage: NCSignalingMessage) {
        guard let peerConnectionWrapper = self.getPeerConnectionWrapper(forSessionId: signalingMessage.from, ofType: signalingMessage.roomType),
              let raised = signalingMessage.payload["state"] as? Bool
        else { return }

        peerConnectionWrapper.setStatusForDataChannelMessageType("raiseHand", withPayload: raised)
    }

    private func processRecording(_ signalingMessage: NCSignalingMessage) {
        guard let recordingMessage = signalingMessage as? NCRecordingMessage
        else { return }

        self.room.callRecording = NCCallRecordingState(rawValue: recordingMessage.status) ?? .stopped
        self.delegate?.callControllerDidChangeRecording(self)
    }

    private func processReaction(_ signalingMessage: NCSignalingMessage) {
        guard let reactionMessage = signalingMessage as? NCReactionMessage,
              let peerConnectionWrapper = self.getPeerConnectionWrapper(forSessionId: signalingMessage.from, ofType: signalingMessage.roomType),
              let reaction = reactionMessage.reaction
        else { return }

        self.delegate?.callController(self, didReceiveReaction: reaction, fromPeer: peerConnectionWrapper)
    }

    private func processUsersInRoom(_ users: [[String: Any]]) {
        WebRTCCommon.shared.assertQueue()

        self.usersInRoom = users

        let previousUserInCall = self.userInCall

        // FIXME: The method changes self.userInCall which should be done here for separation
        let currentSessions = self.getInCallSessions(fromUsersInRoom: users)

        guard !self.isLeavingCall else { return }

        // Detect if user should rejoin call (internal signaling)
        if self.userInCall == 0, self.shouldRejoinCallUsingInternalSignaling {
            self.shouldRejoinCallUsingInternalSignaling = false
            self.shouldRejoinCall()
        }

        if previousUserInCall == 0 {
            // Do nothing if the app user is still not in the call
            if self.userInCall == 0 {
                return
            }

            // Create publisher peer connection
            if let externalSignalingController, externalSignalingController.hasMCU {
                self.createPublisherPeerConnection()
            }
        }

        let oldSessions = self.sessionsInCall

        // Save current sessions in call
        self.sessionsInCall = currentSessions

        // Calculate sessions that left the call
        let leftSessions = Set(oldSessions).subtracting(currentSessions)

        // Calculate sessions sessions that joined the call
        let newSessions = Set(currentSessions).subtracting(oldSessions)

        if !newSessions.isEmpty, self.externalSignalingController == nil {
            self.getPeersForCall()
        }

        self.checkUserPermissionsChange()

        for sessionId in newSessions {
            let peerKey = self.getPeerKey(withSessionId: sessionId, ofType: kRoomTypeVideo, forOwnScreenshare: false)

            guard connectionsDict[peerKey] == nil, sessionId != self.signalingSessionId
            else { continue }

            // Always create a peer connection, so the peer is added to the call view.
            // When using a MCU we request an offer, but in case there are no streams published, we won't get an offer.
            // When using internal signaling if we and the other participant are not publishing any stream,
            // we won't receive or send any offer.
            let peerConnectionWrapper = self.getOrCreatePeerConnectionWrapper(forSessionId: sessionId, withSid: nil, ofType: kRoomTypeVideo)

            if let externalSignalingController, externalSignalingController.hasMCU {
                // Only request offer if the user is sharing audio or video streams
                if self.userHasStreams(sessionId) {
                    print("Requesting offer to the MCU for session: \(sessionId)")
                    self.requestOfferWithRepetition(forSessionId: sessionId, withRoomType: kRoomTypeVideo)
                } else {
                    // Set peer as dummyPeer if it has no streams
                    peerConnectionWrapper.isDummyPeer = true
                }
            } else {
                let result = sessionId.compare(self.signalingSessionId)

                if result == .orderedAscending {
                    print("Creating offer...")
                    peerConnectionWrapper.sendOffer()
                } else {
                    print("Waiting for offer...")
                }

                if self.screensharingActive {
                    // If screensharing is active and we are using internal signaling, we need to send a offer to the newly joined user
                    self.sendScreensharingOffer(toSessionId: peerConnectionWrapper.peerId)
                }
            }
        }

        // Close old peer connections fro sessions that left the call
        for sessionId in leftSessions {
            // Hang up call if user sessionId is no longer in the call
            // Could be because a moderator "ended the call for everyone"
            if sessionId == self.signalingSessionId {
                print("User sessionId is no longer in the call -> hang up call")
                self.delegate?.callControllerWants(toHangUpCall: self)

                return
            }

            // Remove all peer connections for that user
            self.cleanAllPeerConnections(forSessionId: sessionId)
        }
    }

    private func userHasStreams(_ sessionId: String) -> Bool {
        for user in self.usersInRoom {
            if let userSessionId = user["sessionId"] as? String, sessionId == userSessionId, let userCallFlagsRaw = user["inCall"] as? Int {
                let userCallFlags = CallFlag(rawValue: userCallFlagsRaw)

                return userCallFlags.contains(.withAudio) || userCallFlags.contains(.withVideo)
            }
        }

        return false
    }

    private func checkUserPermissionsChange() {
        guard self.room.supportsConversationPermissions else { return }

        for user in self.usersInRoom {
            guard let userSession = user["sessionId"] as? String,
                  let userPermissionValue = user["participantPermissions"] as? Int,
                  userSession == self.signalingSessionId
            else { continue }

            let userPermission = NCPermission(rawValue: userPermissionValue)
            let changedPermissions = userPermission.symmetricDifference(self.room.permissions)

            if changedPermissions.contains(.canPublishAudio) || changedPermissions.contains(.canPublishVideo) || changedPermissions.contains(.canPublishScreen) {
                NCLog.log("User permissions changed")
                self.room.permissions = userPermission

                self.delegate?.callController(self, userPermissionsChanged: userPermission)
                self.forceReconnect()
            }
        }
    }

    private func getInCallSessions(fromUsersInRoom users: [[String: Any]]) -> [String] {
        var sessions = [String]()

        for user in users {
            guard let sessionId = user["sessionId"] as? String,
                  let inCall = user["inCall"] as? Int
            else { continue }

            let internalClient = user["internal"] as? Bool ?? false

            // FIXME: Move to caller
            // Set inCall flag for app user
            if sessionId == self.signalingSessionId {
                self.userInCall = inCall
            }

            // Add session if inCall and if it's not an internal client
            if inCall > 0, !internalClient {
                sessions.append(sessionId)
            }
        }

        return sessions
    }

    public func getActor(fromSessionId sessionId: String) -> TalkActor? {
        WebRTCCommon.shared.assertQueue()

        if let externalSignalingController {
            return externalSignalingController.getParticipant(fromSessionId: sessionId)?.actor
        }

        for user in self.peersInCall {
            if let userSessionId = user["sessionId"] as? String, userSessionId == sessionId {
                let actorId = user["actorId"] as? String
                let actorType = user["actorType"] as? String
                let actorDisplayName = user["displayName"] as? String

                return TalkActor(actorId: actorId, actorType: actorType, actorDisplayName: actorDisplayName)
            }
        }

        return nil
    }

}
