//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import WebRTC

protocol NCSignalingControllerObserver: AnyObject {
    func signalingController(_ signalingController: NCSignalingController, didReceiveSignalingMessage message: [String: Any])
    // The server no longer knows our session in this room, which polling cannot recover from
    func signalingControllerSessionExpired(_ signalingController: NCSignalingController)
}

class NCSignalingController: NSObject {

    // About 45s of retrying with the backoff below
    private static let maxConsecutiveSessionGoneFailures = 5

    weak var observer: NCSignalingControllerObserver?

    private let room: NCRoom
    private var shouldStopPullingMessages = false
    private var consecutivePullFailures = 0
    private var consecutiveSessionGoneFailures = 0
    private var signalingSettings: SignalingSettings?
    private var getSignalingSettingsTask: URLSessionTask?
    private var pullSignalingMessagesTask: URLSessionTask?

    init(for room: NCRoom) {
        self.room = room
        super.init()
    }

    deinit {
        NSLog("NCSignalingController dealloc")
    }

    func updateSignalingSettings(completionBlock block: ((SignalingSettings?) -> Void)?) {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        getSignalingSettingsTask = NCAPIController.sharedInstance().getSignalingSettings(for: activeAccount, forRoom: room.token) { settings, error in
            if let error {
                if (error as NSError).code == NSURLErrorCancelled {
                    return
                }

                // TODO: Error handling
                NCLog.log("Could not get signaling settings. Error: \(error)")
            }

            if let settings {
                self.signalingSettings = settings
            }

            block?(self.signalingSettings)
        }
    }

    func getIceServers() -> [RTCIceServer] {
        guard let signalingSettings else { return [] }

        let stunServers = signalingSettings.stunServers.map {
            RTCIceServer(urlStrings: $0.urls ?? [], username: "", credential: "")
        }

        let turnServers = signalingSettings.turnServers.map {
            RTCIceServer(urlStrings: $0.urls ?? [], username: $0.username, credential: $0.credential)
        }

        return stunServers + turnServers
    }

    func startPullingSignalingMessages() {
        NCLog.log("Start pulling internal signaling messages for token \(room.token ?? "")")

        shouldStopPullingMessages = false
        consecutivePullFailures = 0
        consecutiveSessionGoneFailures = 0

        pullSignalingMessages()
    }

    private func stopPullingSignalingMessages() {
        shouldStopPullingMessages = true
        pullSignalingMessagesTask?.cancel()
    }

    private func pullSignalingMessages() {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        pullSignalingMessagesTask = NCAPIController.sharedInstance().pullSignalingMessages(fromRoom: room.token ?? "", forAccount: activeAccount) { messages, error in
            if self.shouldStopPullingMessages {
                return
            }

            if let error {
                self.consecutivePullFailures += 1

                // A 404 means our session is gone server side, which polling cannot recover from
                if error.responseStatusCode == 404 {
                    self.consecutiveSessionGoneFailures += 1

                    if self.consecutiveSessionGoneFailures >= NCSignalingController.maxConsecutiveSessionGoneFailures {
                        NCLog.log("Internal signaling has no session for token \(self.room.token ?? "") anymore, ending the call")
                        self.shouldStopPullingMessages = true
                        self.observer?.signalingControllerSessionExpired(self)
                        return
                    }
                } else {
                    self.consecutiveSessionGoneFailures = 0
                }

                // The request is only re-armed from here, so retrying immediately would busy loop
                let delay = min(pow(2, Double(min(self.consecutivePullFailures, 4))), 16)
                NCLog.log(String(format: "Could not pull internal signaling messages (failure %ld, status %ld), retrying in %.0fs", self.consecutivePullFailures, error.responseStatusCode, delay))

                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    if self.shouldStopPullingMessages {
                        return
                    }

                    self.pullSignalingMessages()
                }

                return
            }

            self.consecutivePullFailures = 0
            self.consecutiveSessionGoneFailures = 0

            for message in messages ?? [] {
                self.observer?.signalingController(self, didReceiveSignalingMessage: message)
            }

            self.pullSignalingMessages()
        }
    }

    func send(_ message: NCSignalingMessage) {
        guard let jsonSerializedMessages = messagesJSONSerialization([message.messageDict()]) else { return }

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomToken = room.token ?? ""

        Task {
            do {
                try await NCAPIController.sharedInstance().sendSignalingMessages(jsonSerializedMessages, toRoom: roomToken, forAccount: activeAccount)
            } catch {
                // TODO: Error handling
                NSLog("Error sending signaling message.")
            }

            NSLog("Sent %@", jsonSerializedMessages)
        }
    }

    private func messagesJSONSerialization(_ messages: [[AnyHashable: Any]]) -> String? {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: messages)
            return String(data: jsonData, encoding: .utf8)
        } catch {
            NSLog("Error serializing signaling message: %@", error.localizedDescription)
            return nil
        }
    }

    func stopAllRequests() {
        getSignalingSettingsTask?.cancel()
        getSignalingSettingsTask = nil

        stopPullingSignalingMessages()
    }
}
