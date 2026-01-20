//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import WebRTC

@objcMembers
public class NCAudioController: NSObject, RTCAudioSessionDelegate {

    public static let shared = NCAudioController()

    public var rtcAudioSession: RTCAudioSession
    public var isSpeakerActive: Bool = false
    public var numberOfAvailableInputs: Int = 0

    public var isAudioRouteChangeable: Bool {
        if self.numberOfAvailableInputs > 1 {
            return true
        }

        if UIDevice.current.userInterfaceIdiom == .phone {
            // A phone always supports a speaker and earpiece output
            return true
        }

        return false
    }

    public override init() {
        let configuration = RTCAudioSessionConfiguration.webRTC()
        configuration.category = AVAudioSession.Category.playAndRecord.rawValue
        configuration.mode = AVAudioSession.Mode.voiceChat.rawValue
        RTCAudioSessionConfiguration.setWebRTC(configuration)

        self.rtcAudioSession = RTCAudioSession.sharedInstance()
        self.rtcAudioSession.lockForConfiguration()

        do {
            try self.rtcAudioSession.setConfiguration(configuration)
        } catch {
            NCUtils.log("Error setting audio configuration: \(error.localizedDescription)")
        }

        self.rtcAudioSession.unlockForConfiguration()

        if CallKitManager.isCallKitAvailable() {
            self.rtcAudioSession.useManualAudio = true
        }

        super.init()

        self.rtcAudioSession.add(self)

        self.updateRouteInformation()
    }

    // MARK: - Audio session configuration

    public func setAudioSessionToVoiceChatMode() {
        self.changeAudioSessionConfiguration(toMode: .voiceChat)
    }

    public func setAudioSessionToVideoChatMode() {
        self.changeAudioSessionConfiguration(toMode: .videoChat)
    }

    private func changeAudioSessionConfiguration(toMode newMode: AVAudioSession.Mode) {
        WebRTCCommon.shared.assertQueue()

        let configuration = RTCAudioSessionConfiguration.webRTC()
        configuration.category = AVAudioSession.Category.playAndRecord.rawValue
        configuration.mode = newMode.rawValue

        self.rtcAudioSession.lockForConfiguration()

        do {
            if self.rtcAudioSession.isActive {
                try self.rtcAudioSession.setConfiguration(configuration)
            } else {
                try self.rtcAudioSession.setConfiguration(configuration, active: true)
            }
        } catch {
            NCUtils.log("Error setting audio configuration: \(error.localizedDescription)")
        }

        self.rtcAudioSession.unlockForConfiguration()

        self.updateRouteInformation()
    }

    public func disableAudioSession() {
        WebRTCCommon.shared.assertQueue()

        self.rtcAudioSession.lockForConfiguration()

        do {
            try self.rtcAudioSession.setActive(false)
        } catch {
            NCUtils.log("Error setting audio configuration: \(error.localizedDescription)")
        }

        self.rtcAudioSession.unlockForConfiguration()
    }

    private func updateRouteInformation() {
        let audioSession = self.rtcAudioSession.session
        let currentOutput = audioSession.currentRoute.outputs.first

        self.numberOfAvailableInputs = audioSession.availableInputs?.count ?? 0

        if self.rtcAudioSession.mode == AVAudioSession.Mode.videoChat.rawValue || currentOutput?.portType == .builtInSpeaker {
            self.isSpeakerActive = true
        } else {
            self.isSpeakerActive = false
        }

        NotificationCenter.default.post(name: .AudioSessionDidChangeRoutingInformation, object: self)
    }

    public func providerDidActivate(audioSession: AVAudioSession) {
        WebRTCCommon.shared.assertQueue()

        self.rtcAudioSession.audioSessionDidActivate(audioSession)
        self.rtcAudioSession.isAudioEnabled = true

        NotificationCenter.default.post(name: .AudioSessionWasActivatedByProvider, object: self)
    }

    public func providerDidDeactivate(audioSession: AVAudioSession) {
        WebRTCCommon.shared.assertQueue()

        self.rtcAudioSession.audioSessionDidDeactivate(audioSession)
        self.rtcAudioSession.isAudioEnabled = false
    }

    // MARK: RTCAudioSessionDelegate

    public func audioSessionDidChangeRoute(_ session: RTCAudioSession, reason: AVAudioSession.RouteChangeReason, previousRoute: AVAudioSessionRouteDescription) {
        self.updateRouteInformation()

        NotificationCenter.default.post(name: .AudioSessionDidChangeRoute, object: self)
    }

}
