//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import WebRTC

@objc protocol NCPeerConnectionDelegate: AnyObject {

    /// Called when media is received on a new stream from remote peer.
    func peerConnection(_ peerConnection: NCPeerConnection, didAdd stream: RTCMediaStream)

    /// Called when a remote peer closes a stream.
    func peerConnection(_ peerConnection: NCPeerConnection, didRemove stream: RTCMediaStream?)

    /// Called any time the IceConnectionState changes.
    func peerConnection(_ peerConnection: NCPeerConnection, didChange newState: RTCIceConnectionState)

    /// Message received from status data channel.
    func peerConnection(_ peerConnection: NCPeerConnection, didReceiveStatusDataChannelMessage type: String)

    /// Peer's nick received from status data channel.
    func peerConnection(_ peerConnection: NCPeerConnection, didReceivePeerNick nick: String)

    /// New ice candidate has been found.
    func peerConnection(_ peerConnection: NCPeerConnection, didGenerate candidate: RTCIceCandidate)

    /// Called when a peer connection creates a session description.
    func peerConnection(_ peerConnection: NCPeerConnection, needsToSend sessionDescription: RTCSessionDescription)
}

public class NCPeerConnection: NSObject {

    weak var delegate: NCPeerConnectionDelegate?

    var peerId: String
    var sid: String?
    var peerName: String?
    var roomType: String?
    var isAudioOnly = false
    var isMCUPublisherPeer = false
    var isDummyPeer = false
    var isOwnScreensharePeer = false
    var isRemoteAudioDisabled = false
    var isRemoteVideoDisabled = false
    var isPeerSpeaking = false
    var isHandRaised = false
    var showRemoteVideoInOriginalSize = false
    var addedTime: Int = 0

    /// "peerId-sid"
    var peerIdentifier: String {
        if let sid {
            return "\(peerId)-\(sid)"
        }

        return peerId
    }

    private var queuedRemoteCandidates: [RTCIceCandidate]?
    private var peerConnection: RTCPeerConnection?
    private var localDataChannel: RTCDataChannel?
    private var remoteDataChannel: RTCDataChannel?
    private var remoteStream: RTCMediaStream?

    init(sessionId: String, sid: String?, andICEServers iceServers: [Any]?, forAudioOnlyCall audioOnly: Bool) {
        WebRTCCommon.shared.assertQueue()

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

        let config = RTCConfiguration()
        config.iceServers = (iceServers ?? []).compactMap { $0 as? RTCIceServer }
        config.sdpSemantics = .unifiedPlan

        self.peerId = sessionId
        self.sid = sid ?? String(format: "%.0f", Date().timeIntervalSince1970 * 1000)
        self.isAudioOnly = audioOnly
        self.isRemoteAudioDisabled = true
        self.isRemoteVideoDisabled = true

        super.init()

        let peerConnectionFactory = WebRTCCommon.shared.peerConnectionFactory
        self.peerConnection = peerConnectionFactory.peerConnection(with: config, constraints: constraints, delegate: self)
    }

    convenience init?(forPublisherWithSessionId sessionId: String, andICEServers iceServers: [Any]?, forAudioOnlyCall audioOnly: Bool) {
        self.init(sessionId: sessionId, sid: nil, andICEServers: iceServers, forAudioOnlyCall: audioOnly)
        self.isMCUPublisherPeer = true
    }

    deinit {
        NSLog("NCPeerConnection deinit")
    }

    // MARK: - NSObject

    public override var hash: Int {
        return peerIdentifier.hash
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let otherConnection = object as? NCPeerConnection else {
            return false
        }

        // Identify a peer by its peerIdentifier ("peerId-sid"), consistent with `hash` and with the
        // collection view / renderer bookkeeping. Comparing the underlying peerConnection reference
        // instead would treat a recreated wrapper for the same participant as a different peer, which
        // breaks the diffable data source's identity and the contains/firstIndex guards built on it.
        return otherConnection.peerIdentifier == self.peerIdentifier
    }

    // MARK: - Public

    func add(_ candidate: RTCIceCandidate) {
        WebRTCCommon.shared.assertQueue()

        guard peerConnection?.remoteDescription != nil else {
            if queuedRemoteCandidates == nil {
                queuedRemoteCandidates = []
            }

            NSLog("Queued a remote ICE candidate for later.")
            queuedRemoteCandidates?.append(candidate)
            return
        }

        NSLog("Adding a remote ICE candidate.")
        peerConnection?.add(candidate) { error in
            if error != nil {
                NSLog("Error while adding a remote ICE candidate.")
            }
        }
    }

    func drainRemoteCandidates() {
        WebRTCCommon.shared.assertQueue()

        NSLog("Drain %lu remote ICE candidates.", queuedRemoteCandidates?.count ?? 0)

        for candidate in queuedRemoteCandidates ?? [] {
            peerConnection?.add(candidate) { error in
                if error != nil {
                    NSLog("Error while adding a remote ICE candidate.")
                }
            }
        }

        queuedRemoteCandidates = nil
    }

    func setRemoteDescription(_ sessionDescription: RTCSessionDescription?) {
        WebRTCCommon.shared.assertQueue()

        guard let sessionDescription, let sdpPreferringCodec = ARDSDPUtils.description(for: sessionDescription, preferredVideoCodec: "H264") else {
            return
        }
        peerConnection?.setRemoteDescription(sdpPreferringCodec) { [weak self] error in
            WebRTCCommon.shared.dispatch {
                self?.peerConnectionDidSetRemoteSessionDescription(sdpPreferringCodec, error: error)
            }
        }
    }

    func sendOffer() {
        sendOffer(with: defaultOfferConstraints())
    }

    func sendPublisherOffer() {
        sendOffer(with: publisherOfferConstraints())
    }

    private func sendOffer(with constraints: RTCMediaConstraints) {
        WebRTCCommon.shared.assertQueue()

        // Create data channel before creating the offer to enable data channels
        let config = RTCDataChannelConfiguration()
        config.isNegotiated = false
        localDataChannel = peerConnection?.dataChannel(forLabel: "status", configuration: config)
        localDataChannel?.delegate = self

        // Create offer
        peerConnection?.offer(for: constraints) { [weak self] sdp, error in
            WebRTCCommon.shared.dispatch {
                self?.peerConnectionDidCreateLocalSessionDescription(sdp, error: error)
            }
        }
    }

    func setStatusForDataChannelMessageType(_ type: String, withPayload payload: Any?) {
        WebRTCCommon.shared.assertQueue()

        if type == "nickChanged" {
            var nick = ""
            if let payload = payload as? String {
                nick = payload
            } else if let payload = payload as? [String: Any], let name = payload["name"] as? String {
                nick = name
            }
            peerName = nick
            delegate?.peerConnection(self, didReceivePeerNick: nick)
        } else {
            // Check remote audio/video status
            switch type {
            case "audioOn":
                isRemoteAudioDisabled = false
            case "audioOff":
                isRemoteAudioDisabled = true
            case "videoOn":
                isRemoteVideoDisabled = false
            case "videoOff":
                isRemoteVideoDisabled = true
            case "speaking":
                isPeerSpeaking = true
            case "stoppedSpeaking":
                isPeerSpeaking = false
            case "raiseHand":
                isHandRaised = (payload as? Bool) ?? false
            default:
                break
            }

            delegate?.peerConnection(self, didReceiveStatusDataChannelMessage: type)
        }
    }

    func close() {
        WebRTCCommon.shared.assertQueue()

        if let localStream = peerConnection?.localStreams.first {
            peerConnection?.remove(localStream)
        }
        peerConnection?.close()

        remoteStream = nil
        localDataChannel = nil
        remoteDataChannel = nil
        peerConnection = nil
    }

    // MARK: - Public RTC getters

    func getPeerConnection() -> RTCPeerConnection? {
        WebRTCCommon.shared.assertQueue()
        return peerConnection
    }

    func getLocalDataChannel() -> RTCDataChannel? {
        WebRTCCommon.shared.assertQueue()
        return localDataChannel
    }

    func getRemoteDataChannel() -> RTCDataChannel? {
        WebRTCCommon.shared.assertQueue()
        return remoteDataChannel
    }

    func getRemoteStream() -> RTCMediaStream? {
        WebRTCCommon.shared.assertQueue()
        return remoteStream
    }

    func hasRemoteStream() -> Bool {
        return remoteStream != nil
    }

    // MARK: - Data channel message helpers

    func sendDataChannelMessage(ofType type: String, withPayload payload: Any?) {
        WebRTCCommon.shared.assertQueue()

        var message: [String: Any] = ["type": type]
        if let payload {
            message["payload"] = payload
        }

        guard let jsonMessage = createDataChannelMessage(message) else {
            return
        }

        let dataBuffer = RTCDataBuffer(data: jsonMessage, isBinary: false)

        if let localDataChannel {
            localDataChannel.sendData(dataBuffer)
        } else if let remoteDataChannel {
            remoteDataChannel.sendData(dataBuffer)
        } else {
            NSLog("No data channel opened")
        }
    }

    private func dataChannelMessage(fromJSONData jsonData: Data) -> [AnyHashable: Any]? {
        do {
            return try JSONSerialization.jsonObject(with: jsonData) as? [AnyHashable: Any]
        } catch {
            NSLog("Error parsing data channel message: %@", error.localizedDescription)
            return nil
        }
    }

    private func createDataChannelMessage(_ message: [String: Any]) -> Data? {
        do {
            return try JSONSerialization.data(withJSONObject: message)
        } catch {
            NSLog("Error creating data channel message: %@", error.localizedDescription)
            return nil
        }
    }

    // MARK: - RTCSessionDescriptionDelegate
    // Delegates from RTCSessionDescription are already dispatched to the webrtc client thread

    private func peerConnectionDidCreateLocalSessionDescription(_ sdp: RTCSessionDescription?, error: Error?) {
        if let error {
            NSLog("Failed to create local session description for peer %@. Error: %@", peerId, error.localizedDescription)
            return
        }

        WebRTCCommon.shared.assertQueue()

        guard let sdp else {
            return
        }

        // Set H264 as preferred codec.
        guard let sdpPreferringCodec = ARDSDPUtils.description(for: sdp, preferredVideoCodec: "H264") else {
            return
        }

        peerConnection?.setLocalDescription(sdpPreferringCodec) { [weak self] error in
            if let error {
                NSLog("Failed to set local session description: %@", error.localizedDescription)
                return
            }

            WebRTCCommon.shared.dispatch {
                guard let self else { return }
                self.delegate?.peerConnection(self, needsToSend: sdpPreferringCodec)
            }
        }
    }

    private func peerConnectionDidSetRemoteSessionDescription(_ sessionDescription: RTCSessionDescription, error: Error?) {
        if let error {
            NSLog("Failed to set remote session description for peer %@. Error: %@", peerId, error.localizedDescription)
            return
        }

        WebRTCCommon.shared.assertQueue()

        // If we just set a remote offer we need to create an answer and set it as local description.
        if peerConnection?.signalingState == .haveRemoteOffer {
            // Create data channel before sending answer
            let config = RTCDataChannelConfiguration()
            config.isNegotiated = false
            localDataChannel = peerConnection?.dataChannel(forLabel: "status", configuration: config)
            localDataChannel?.delegate = self

            // Stop video transceiver in audio only peer connections
            // Constraints are no longer supported when creating answers (with Unified Plan semantics)
            if isAudioOnly {
                for transceiver in peerConnection?.transceivers ?? [] where transceiver.mediaType == .video {
                    transceiver.stopInternal()
                    NSLog("Stop video transceiver in audio only peer connections.")
                }
            }

            // Create answer
            peerConnection?.answer(for: defaultAnswerConstraints()) { [weak self] sdp, error in
                WebRTCCommon.shared.dispatch {
                    self?.peerConnectionDidCreateLocalSessionDescription(sdp, error: error)
                }
            }
        }

        if peerConnection?.remoteDescription != nil {
            drainRemoteCandidates()
        }
    }

    // MARK: - Utils

    private func defaultAnswerConstraints() -> RTCMediaConstraints {
        return defaultOfferConstraints()
    }

    private func defaultOfferConstraints() -> RTCMediaConstraints {
        let mandatoryConstraints = [
            "OfferToReceiveAudio": "true",
            "OfferToReceiveVideo": isAudioOnly ? "false" : "true"
        ]

        let optionalConstraints = [
            "internalSctpDataChannels": "true",
            "DtlsSrtpKeyAgreement": "true"
        ]

        return RTCMediaConstraints(mandatoryConstraints: mandatoryConstraints, optionalConstraints: optionalConstraints)
    }

    private func publisherOfferConstraints() -> RTCMediaConstraints {
        let mandatoryConstraints = [
            "OfferToReceiveAudio": "false",
            "OfferToReceiveVideo": "false"
        ]

        let optionalConstraints = [
            "internalSctpDataChannels": "true",
            "DtlsSrtpKeyAgreement": "true"
        ]

        return RTCMediaConstraints(mandatoryConstraints: mandatoryConstraints, optionalConstraints: optionalConstraints)
    }

    private func stringForSignalingState(_ state: RTCSignalingState) -> String {
        switch state {
        case .stable:
            return "Stable"
        case .haveLocalOffer:
            return "Have Local Offer"
        case .haveRemoteOffer:
            return "Have Remote Offer"
        case .closed:
            return "Closed"
        default:
            return "Other state"
        }
    }

    private func stringForConnectionState(_ state: RTCIceConnectionState) -> String {
        switch state {
        case .new:
            return "New"
        case .checking:
            return "Checking"
        case .connected:
            return "Connected"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .disconnected:
            return "Disconnected"
        case .closed:
            return "Closed"
        default:
            return "Other state"
        }
    }

    private func stringForGatheringState(_ state: RTCIceGatheringState) -> String {
        switch state {
        case .new:
            return "New"
        case .gathering:
            return "Gathering"
        case .complete:
            return "Complete"
        default:
            return "Other state"
        }
    }
}

// MARK: - RTCPeerConnectionDelegate
// Delegates from RTCPeerConnection are called on the "signaling_thread" of WebRTC

extension NCPeerConnection: RTCPeerConnectionDelegate {

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        NSLog("Signaling state with '%@' changed to: %@", peerId, stringForSignalingState(stateChanged))
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        WebRTCCommon.shared.dispatch {
            NSLog("Received %lu video tracks and %lu audio tracks from %@", stream.videoTracks.count, stream.audioTracks.count, self.peerId)

            self.remoteStream = stream

            if stream.videoTracks.isEmpty {
                self.isRemoteVideoDisabled = true
            }

            self.delegate?.peerConnection(self, didAdd: stream)
        }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        WebRTCCommon.shared.dispatch {
            NSLog("Stream was removed from %@", self.peerId)
            self.remoteStream = nil
            self.delegate?.peerConnection(self, didRemove: stream)
        }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        WebRTCCommon.shared.dispatch {
            guard let stream = mediaStreams.first else {
                return
            }

            NSLog("Received %lu video tracks and %lu audio tracks from %@", stream.videoTracks.count, stream.audioTracks.count, self.peerId)

            self.remoteStream = stream
            self.delegate?.peerConnection(self, didAdd: stream)
        }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {
        WebRTCCommon.shared.dispatch {
            NSLog("Receiver was removed from %@", self.peerId)
            self.remoteStream = nil
            self.delegate?.peerConnection(self, didRemove: nil)
        }
    }

    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        NSLog("WARNING: Renegotiation needed but unimplemented.")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        WebRTCCommon.shared.dispatch {
            NSLog("ICE state with '%@' changed to: %@", self.peerId, self.stringForConnectionState(newState))
            self.delegate?.peerConnection(self, didChange: newState)
        }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        NSLog("ICE gathering state with '%@' changed to : %@", peerId, stringForGatheringState(newState))
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        WebRTCCommon.shared.dispatch {
            NSLog("Peer '%@' did generate Ice Candidate: %@", self.peerId, candidate)
            self.delegate?.peerConnection(self, didGenerate: candidate)
        }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        NSLog("PeerConnection didRemoveIceCandidates delegate has been called.")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        WebRTCCommon.shared.dispatch {
            if let remoteDataChannel = self.remoteDataChannel {
                NSLog("Remote data channel with label '%@' exists, but received open event for data channel with label '%@'", remoteDataChannel.label, dataChannel.label)
            }

            self.remoteDataChannel = dataChannel
            self.remoteDataChannel?.delegate = self
            NSLog("Remote data channel '%@' was opened.", dataChannel.label)
        }
    }
}

// MARK: - RTCDataChannelDelegate
// Delegates from RTCDataChannel are called on the "signaling_thread" of WebRTC

extension NCPeerConnection: RTCDataChannelDelegate {

    public func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        WebRTCCommon.shared.dispatch {
            NSLog("Data channel '%@' did change state: %ld", dataChannel.label, dataChannel.readyState.rawValue)
        }
    }

    public func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        WebRTCCommon.shared.dispatch {
            guard let message = self.dataChannelMessage(fromJSONData: buffer.data),
                  let messageType = message["type"] as? String else {
                return
            }

            let messagePayload = message["payload"]
            self.setStatusForDataChannelMessageType(messageType, withPayload: messagePayload)
        }
    }
}
