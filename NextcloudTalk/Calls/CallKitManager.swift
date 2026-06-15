//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import CallKit
import AVFoundation

public extension NSNotification.Name {
    static let CallKitManagerDidAnswerCall = NSNotification.Name("CallKitManagerDidAnswerCallNotification")
    static let CallKitManagerDidEndCall = NSNotification.Name("CallKitManagerDidEndCallNotification")
    static let CallKitManagerDidStartCall = NSNotification.Name("CallKitManagerDidStartCallNotification")
    static let CallKitManagerDidChangeAudioMute = NSNotification.Name("CallKitManagerDidChangeAudioMuteNotification")
    static let CallKitManagerWantsToUpgradeToVideoCall = NSNotification.Name("CallKitManagerWantsToUpgradeToVideoCall")
    static let CallKitManagerDidFailRequestingCallTransaction = NSNotification.Name("CallKitManagerDidFailRequestingCallTransaction")
}

@objcMembers
public class CallKitCall: NSObject {

    public var uuid: UUID?
    public var token: String?
    public var displayName: String?
    public var accountId: String?
    public var update: CXCallUpdate?
    public var reportedWhileInCall: Bool = false
    public var isRinging: Bool = false
    public var initiator: Bool = false
    public var silentCall: Bool = false
    public var recordingConsent: Bool = false
}

@objcMembers
public class CallKitManager: NSObject, CXProviderDelegate {

    static let shared = CallKitManager()

    @available(*, renamed: "shared")
    static func sharedInstance() -> CallKitManager {
        return CallKitManager.shared
    }

    private static let maxRingingTimeSeconds: TimeInterval = 45.0
    private static let checkCallStateEverySeconds: TimeInterval = 5.0

    public var calls: [UUID: CallKitCall] = [:] // uuid -> callKitCall
    private var hangUpTimers: [UUID: Timer] = [:] // uuid -> hangUpTimer
    private var callStateTimers: [UUID: Timer] = [:] // uuid -> callStateTimer

    private var provider: CXProvider
    private lazy var callController = CXCallController()

    private var startCallRetried: Bool = false

    override init() {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = true
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.includesCallsInRecents = NCUserDefaults.includeCallsInRecents()
        configuration.supportedHandleTypes = [.phoneNumber, .emailAddress, .generic]
        configuration.iconTemplateImageData = UIImage(named: "app-logo-callkit")?.pngData()

        let provider = CXProvider(configuration: configuration)
        self.provider = provider

        super.init()

        provider.setDelegate(self, queue: nil)
    }

    public class func isCallKitAvailable() -> Bool {
        if NCUtils.isiOSAppOnMac() {
            // There's currently no support for CallKit when running on MacOS.
            // If this is enabled on MacOS, there's no audio, because we fail to retrieve
            // the streams from CallKit. Tested with MacOS 12 & 13.
            return false
        }

        // CallKit should be deactivated in China as requested by Apple
        return Locale.current.regionCode != "CN"
    }

    // MARK: - Utils

    private func defaultCallUpdate() -> CXCallUpdate {
        let update = CXCallUpdate()
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        update.hasVideo = false

        return update
    }

    private func call(forToken token: String) -> CallKitCall? {
        for call in self.calls.values where call.token == token {
            return call
        }

        return nil
    }

    // MARK: - Actions

    public func setIncludeInRecents(toValue value: Bool) {
        self.provider.configuration.includesCallsInRecents = value
    }

    public func reportIncomingCall(_ token: String, withDisplayName displayName: String, forAccountId accountId: String) {
        var protectedDataAvailable = "available"

        if !UIApplication.shared.isProtectedDataAvailable {
            protectedDataAvailable = "unavailable"
        }

        NCLog.log("Report incoming call for token \(token) for account \(accountId). Protected data is \(protectedDataAvailable)")

        let ongoingCalls = !self.calls.isEmpty
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        if NCSettingsController.sharedInstance().isEndToEndEncryptedCallingEnabled(forAccount: activeAccount.accountId) {
            self.reportAndCancelIncomingCall(token, forAccountId: accountId, withLocalNotificationType: .endToEndEncryptionUnsupported)
            return
        }

        // If the app is not active (e.g. in background) and there is an open chat
        let isAppActive = UIApplication.shared.applicationState == .active
        if !isAppActive, let chatViewController = NCRoomsManager.shared.chatViewController {
            // Leave the chat so it doesn't try to join the chat conversation when the app becomes active.
            chatViewController.leaveChat()
            NCUserInterfaceController.sharedInstance().presentConversationsList()
        }

        // If the incoming call is from a different account
        if activeAccount.accountId != accountId {
            if ongoingCalls {
                // If there is an ongoing call then show a local notification
                self.reportAndCancelIncomingCall(token, forAccountId: accountId, withLocalNotificationType: .cancelledCall)
                return
            } else {
                // Change accounts if there are no ongoing calls
                NCSettingsController.sharedInstance().setActiveAccountWithAccountId(accountId)
            }
        }

        let update = self.defaultCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: token)
        update.localizedCallerName = displayName

        let callUUID = UUID()
        let call = CallKitCall()
        call.uuid = callUUID
        call.token = token
        call.displayName = displayName
        call.accountId = accountId
        call.update = update
        call.reportedWhileInCall = ongoingCalls
        call.isRinging = true

        self.provider.reportNewIncomingCall(with: callUUID, update: update) { [weak self] error in
            guard let self else { return }

            guard error == nil else {
                print("Provider could not present incoming call view.")
                return
            }

            // Add call to calls array
            self.calls[callUUID] = call

            // Add hangUpTimer to timers array
            let hangUpTimer = Timer.scheduledTimer(withTimeInterval: CallKitManager.maxRingingTimeSeconds, repeats: false) { [weak self] _ in
                self?.endCallWithMissedCallNotification(for: call)
            }
            self.hangUpTimers[callUUID] = hangUpTimer

            // Add callStateTimer to timers array
            let callStateTimer = Timer.scheduledTimer(withTimeInterval: CallKitManager.checkCallStateEverySeconds, repeats: false) { [weak self] _ in
                self?.checkCallState(for: call)
            }
            self.callStateTimers[callUUID] = callStateTimer

            // Get call info from server
            self.getCallInfo(for: call)
        }
    }

    private func reportAndCancelIncomingCall(_ token: String, forAccountId accountId: String, withLocalNotificationType notificationType: NCLocalNotificationType) {
        let update = self.defaultCallUpdate()
        let callUUID = UUID()
        let call = CallKitCall()
        call.uuid = callUUID
        call.token = token
        call.accountId = accountId
        call.update = update

        self.provider.reportNewIncomingCall(with: callUUID, update: update) { [weak self] error in
            guard let self else { return }

            guard error == nil else {
                print("Provider could not present incoming call view.")
                return
            }

            self.calls[callUUID] = call

            let userInfo: [String: Any] = [
                "roomToken": token,
                "localNotificationType": notificationType.rawValue,
                "accountId": accountId
            ]

            NCNotificationController.sharedInstance().show(notificationType, withUserInfo: userInfo)
            self.endCall(withUUID: callUUID)
        }
    }

    public func reportIncomingCallForNonCallKitDevices(withPushNotification pushNotification: NCPushNotification) {
        let update = self.defaultCallUpdate()
        let callUUID = UUID()
        let call = CallKitCall()
        call.uuid = callUUID
        call.token = pushNotification.roomToken
        call.accountId = pushNotification.accountId
        call.update = update

        self.provider.reportNewIncomingCall(with: callUUID, update: update) { [weak self] error in
            guard let self else { return }

            guard error == nil else {
                print("Provider could not present incoming call view.")
                return
            }

            self.calls[callUUID] = call
            NCNotificationController.sharedInstance().showLocalNotificationForIncomingCall(withPushNotificaion: pushNotification)
            self.endCall(withUUID: callUUID)
        }
    }

    public func reportIncomingCallForOldAccount() {
        let update = self.defaultCallUpdate()
        update.localizedCallerName = NSLocalizedString("Old account", comment: "Will be used as the caller name when a VoIP notification can't be decrypted")

        let callUUID = UUID()
        let call = CallKitCall()
        call.uuid = callUUID
        call.update = update

        self.provider.reportNewIncomingCall(with: callUUID, update: update) { [weak self] error in
            guard let self else { return }

            guard error == nil else {
                print("Provider could not present incoming call view.")
                return
            }

            self.calls[callUUID] = call
            let userInfo: [String: Any] = ["localNotificationType": NCLocalNotificationType.callFromOldAccount.rawValue]
            NCNotificationController.sharedInstance().show(.callFromOldAccount, withUserInfo: userInfo)
            self.endCall(withUUID: callUUID)
        }
    }

    private func getCallInfo(for call: CallKitCall) {
        guard let token = call.token, let accountId = call.accountId else { return }

        if let room = NCDatabaseManager.sharedInstance().room(withToken: token, forAccountId: accountId) {
            self.updateCall(call, withDisplayName: room.displayName)
        }

        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId) else { return }

        NCAPIController.sharedInstance().getRoom(forAccount: account, withToken: token) { [weak self] roomDict, error in
            guard let self, error == nil else { return }

            if let room = NCRoom(dictionary: roomDict, andAccountId: accountId) {
                self.updateCall(call, withDisplayName: room.displayName)
            }

            if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityCallFlags, forAccountId: accountId) {
                let callFlagRaw = roomDict?["callFlag"] as? Int ?? 0
                let callFlag = CallFlag(rawValue: callFlagRaw)

                if callFlag.isEmpty {
                    self.presentMissedCallNotification(for: call)
                    self.endCall(withUUID: call.uuid)
                } else if callFlag.contains(.withVideo) {
                    self.updateCall(call, hasVideo: true)
                }
            }
        }
    }

    private func updateCall(_ call: CallKitCall, withDisplayName displayName: String) {
        guard let uuid = call.uuid, let update = call.update else { return }

        call.displayName = displayName
        update.localizedCallerName = displayName

        self.provider.reportCall(with: uuid, updated: update)
    }

    private func updateCall(_ call: CallKitCall, hasVideo: Bool) {
        guard let uuid = call.uuid, let update = call.update else { return }

        update.hasVideo = hasVideo

        self.provider.reportCall(with: uuid, updated: update)
    }

    private func stopHangUpTimer(forCallUUID uuid: UUID) {
        if let hangUpTimer = self.hangUpTimers[uuid] {
            hangUpTimer.invalidate()
            self.hangUpTimers.removeValue(forKey: uuid)
        }
    }

    private func stopCallStateTimer(forCallUUID uuid: UUID) {
        if let callStateTimer = self.callStateTimers[uuid] {
            callStateTimer.invalidate()
            self.callStateTimers.removeValue(forKey: uuid)
        }
    }

    private func endCallWithMissedCallNotification(for call: CallKitCall) {
        self.presentMissedCallNotification(for: call)
        self.endCall(withUUID: call.uuid)
    }

    private func presentMissedCallNotification(for call: CallKitCall?) {
        guard let call, let token = call.token, let accountId = call.accountId else { return }

        let userInfo: [String: Any] = [
            "roomToken": token,
            "displayName": call.displayName,
            "localNotificationType": NCLocalNotificationType.missedCall.rawValue,
            "accountId": accountId
        ]

        NCNotificationController.sharedInstance().show(.missedCall, withUserInfo: userInfo)
    }

    private func checkCallState(for call: CallKitCall) {
        guard let accountId = call.accountId else { return }

        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityCallNotificationState, forAccountId: accountId) {
            self.checkCallStateWithStateApi(for: call)
        } else {
            self.checkCallStateWithPeers(for: call)
        }
    }

    private func checkCallStateWithStateApi(for call: CallKitCall) {
        guard let token = call.token, let accountId = call.accountId else { return }

        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId) else { return }

        NCAPIController.sharedInstance().getCallNotificationState(for: account, forRoom: token) { [weak self] state in
            guard let self else { return }

            // Make sure call is still ringing at this point to avoid a race-condition between answering the call on this device and the API callback
            if !call.isRinging {
                return
            }

            if state == .roomNotFound {
                // The conversation was not found for this participant
                // Mostlikely the conversation was removed while an incoming call was ongoing
                self.endCall(withUUID: call.uuid)
                return
            } else if state == .missedCall {
                // No one is in the call, we can hang up and show missed call notification
                self.presentMissedCallNotification(for: call)
                self.endCall(withUUID: call.uuid)
                return
            } else if state == .participantJoined {
                // Account is already in a call (answered the call on a different device) -> no need to keep ringing

                if !NCRoomsManager.shared.isCallOngoing(withCallToken: token) {
                    self.endCall(withUUID: call.uuid)
                }

                return
            }

            // Reschedule next check
            if let uuid = call.uuid {
                let callStateTimer = Timer.scheduledTimer(withTimeInterval: CallKitManager.checkCallStateEverySeconds, repeats: false) { [weak self] _ in
                    self?.checkCallState(for: call)
                }
                self.callStateTimers[uuid] = callStateTimer
            }
        }
    }

    private func checkCallStateWithPeers(for call: CallKitCall) {
        guard let token = call.token, let accountId = call.accountId else { return }

        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId) else { return }

        NCAPIController.sharedInstance().getPeersForCall(inRoom: token, forAccount: account) { [weak self] peers, error, statusCode in
            guard let self else { return }

            // Make sure call is still ringing at this point to avoid a race-condition between answering the call on this device and the API callback
            if !call.isRinging {
                return
            }

            if statusCode == 404 {
                // The conversation was not found for this participant
                // Mostlikely the conversation was removed while an incoming call was ongoing
                self.endCall(withUUID: call.uuid)
                return
            }

            let peers = peers ?? []

            if error == nil, peers.isEmpty {
                // No one is in the call, we can hang up and show missed call notification
                self.presentMissedCallNotification(for: call)
                self.endCall(withUUID: call.uuid)
                return
            }

            for user in peers {
                let userId = user["actorId"] as? String
                let isUserActorType = (user["actorType"] as? String) == "users"

                if account.userId == userId, isUserActorType {
                    // Account is already in a call (answered the call on a different device) -> no need to keep ringing
                    self.endCall(withUUID: call.uuid)
                    return
                }
            }

            // Reschedule next check
            if let uuid = call.uuid {
                let callStateTimer = Timer.scheduledTimer(withTimeInterval: CallKitManager.checkCallStateEverySeconds, repeats: false) { [weak self] _ in
                    self?.checkCallState(for: call)
                }
                self.callStateTimers[uuid] = callStateTimer
            }
        }
    }

    public func startCall(_ token: String, withVideoEnabled videoEnabled: Bool, andDisplayName displayName: String, asInitiator initiator: Bool, silently: Bool, recordingConsent: Bool, withAccountId accountId: String) {
        if NCSettingsController.sharedInstance().isEndToEndEncryptedCallingEnabled(forAccount: accountId) {
            let userInfo: [String: Any] = [
                "roomToken": token,
                "localNotificationType": NCLocalNotificationType.endToEndEncryptionUnsupported.rawValue,
                "accountId": accountId
            ]

            NCNotificationController.sharedInstance().show(.endToEndEncryptionUnsupported, withUserInfo: userInfo)
            return
        }

        if !CallKitManager.isCallKitAvailable() {
            let userInfo: [String: Any] = [
                "roomToken": token,
                "isVideoEnabled": videoEnabled,
                "initiator": initiator,
                "silentCall": silently,
                "recordingConsent": recordingConsent,
                "accountId": accountId
            ]

            NotificationCenter.default.post(name: .CallKitManagerDidStartCall, object: self, userInfo: userInfo)
            return
        }

        // Start a new call
        if self.calls.isEmpty {
            let update = self.defaultCallUpdate()
            let handle = CXHandle(type: .generic, value: token)
            update.remoteHandle = handle
            update.localizedCallerName = displayName
            update.hasVideo = videoEnabled

            let callUUID = UUID()
            let call = CallKitCall()
            call.uuid = callUUID
            call.token = token
            call.displayName = displayName
            call.accountId = accountId
            call.update = update
            call.initiator = initiator
            call.silentCall = silently
            call.recordingConsent = recordingConsent

            let startCallAction = CXStartCallAction(call: callUUID, handle: handle)
            startCallAction.isVideo = videoEnabled
            startCallAction.contactIdentifier = displayName
            let transaction = CXTransaction()
            transaction.addAction(startCallAction)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }

                self.callController.request(transaction) { [weak self] error in
                    guard let self else { return }

                    if error == nil {
                        self.startCallRetried = false
                        self.calls[callUUID] = call
                    } else {
                        if self.startCallRetried {
                            NSLog("%@", error?.localizedDescription ?? "")
                            self.startCallRetried = false
                            let userInfo: [String: Any] = ["roomToken": token]
                            NotificationCenter.default.post(name: .CallKitManagerDidFailRequestingCallTransaction, object: self, userInfo: userInfo)
                        } else {
                            self.startCallRetried = true
                            self.startCall(token, withVideoEnabled: videoEnabled, andDisplayName: displayName, asInitiator: initiator, silently: silently, recordingConsent: recordingConsent, withAccountId: accountId)
                        }
                    }
                }
            }
        // Send notification for video call upgrade.
        // Since we send the token in the notification, it will only ask
        // for an upgrade if there is an ongoing (audioOnly) call in that room.
        } else if videoEnabled {
            let userInfo: [String: Any] = ["roomToken": token]
            NotificationCenter.default.post(name: .CallKitManagerWantsToUpgradeToVideoCall, object: self, userInfo: userInfo)
        }
    }

    private func presentRecordingConsentRequiredNotification(for call: CallKitCall?) {
        guard let call, let token = call.token, let accountId = call.accountId else { return }

        let userInfo: [String: Any] = [
            "roomToken": token,
            "displayName": call.displayName,
            "localNotificationType": NCLocalNotificationType.recordingConsentRequired.rawValue,
            "accountId": accountId
        ]

        NCNotificationController.sharedInstance().show(.recordingConsentRequired, withUserInfo: userInfo)
    }

    public func endCall(_ token: String, withStatusCode statusCode: Int) {
        NCLog.log("End call for token \(token) with statusCode \(statusCode)")

        if let call = self.call(forToken: token) {
            // Check if recording consent is required
            if statusCode == 400 {
                self.presentRecordingConsentRequiredNotification(for: call)
            }

            self.endCall(withUUID: call.uuid)
        }
    }

    private func endCall(withUUID uuid: UUID?) {
        guard let uuid, let call = self.calls[uuid], let callUUID = call.uuid else { return }

        let endCallAction = CXEndCallAction(call: callUUID)
        let transaction = CXTransaction()
        transaction.addAction(endCallAction)
        self.callController.request(transaction) { error in
            if let error {
                NSLog("%@", error.localizedDescription)
            }
        }
    }

    public func changeAudioMuted(_ muted: Bool, forCall token: String) {
        guard let call = self.call(forToken: token), let callUUID = call.uuid else { return }

        let muteAction = CXSetMutedCallAction(call: callUUID, muted: muted)
        let transaction = CXTransaction()
        transaction.addAction(muteAction)
        self.callController.request(transaction) { error in
            if let error {
                NSLog("%@", error.localizedDescription)
            }
        }
    }

    public func switchCall(from: String, toCall to: String) {
        if let call = self.call(forToken: from) {
            call.token = to
        }
    }

    // MARK: - CXProviderDelegate

    public func providerDidReset(_ provider: CXProvider) {
        NSLog("Provider:didReset")
    }

    public func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        if let call = self.calls[action.callUUID], let uuid = call.uuid, let update = call.update {
            // Seems to be needed to display the call name correctly
            self.provider.reportCall(with: uuid, updated: update)

            // Report outgoing call
            provider.reportOutgoingCall(with: action.callUUID, connectedAt: Date())
            let userInfo: [String: Any] = [
                "roomToken": action.handle.value,
                "isVideoEnabled": action.isVideo,
                "initiator": call.initiator,
                "silentCall": call.silentCall,
                "recordingConsent": call.recordingConsent,
                "accountId": call.accountId
            ]

            NotificationCenter.default.post(name: .CallKitManagerDidStartCall, object: self, userInfo: userInfo)
        }

        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        if let call = self.calls[action.callUUID], let uuid = call.uuid, let token = call.token {
            NCLog.log("CallKit provider answer call action for token \(token)")

            call.isRinging = false
            self.stopCallStateTimer(forCallUUID: uuid)

            self.stopHangUpTimer(forCallUUID: uuid)
            let userInfo: [String: Any] = [
                "roomToken": token,
                "hasVideo": call.update?.hasVideo ?? false,
                "waitForCallEnd": call.reportedWhileInCall,
                "accountId": call.accountId
            ]

            NotificationCenter.default.post(name: .CallKitManagerDidAnswerCall, object: self, userInfo: userInfo)
        }

        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        if let call = self.calls[action.callUUID], let uuid = call.uuid {
            // Token can be `null` here, when we were unable to decrypt the push notification (e.g. we received one for an old account)
            NCLog.log("CallKit provider end call action for token \(call.token ?? "(null)")")

            call.isRinging = false
            self.stopCallStateTimer(forCallUUID: uuid)

            self.stopHangUpTimer(forCallUUID: uuid)
            let leaveCallToken = call.token
            self.calls.removeValue(forKey: action.callUUID)

            if let leaveCallToken {
                let userInfo: [String: Any] = ["roomToken": leaveCallToken]
                NotificationCenter.default.post(name: .CallKitManagerDidEndCall, object: self, userInfo: userInfo)
            }
        }

        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        if let call = self.calls[action.callUUID], let token = call.token {
            var userInfo: [String: Any] = ["roomToken": token]
            userInfo["isMuted"] = action.isMuted
            NotificationCenter.default.post(name: .CallKitManagerDidChangeAudioMute, object: self, userInfo: userInfo)
        }

        action.fulfill()
    }

    public func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        NSLog("Provider:didActivateAudioSession - %@", audioSession)

        WebRTCCommon.shared.dispatch {
            NCAudioController.shared.providerDidActivate(audioSession: audioSession)
        }
    }

    public func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        NSLog("Provider:didDeactivateAudioSession - %@", audioSession)

        WebRTCCommon.shared.dispatch {
            NCAudioController.shared.providerDidDeactivate(audioSession: audioSession)
        }
    }
}
