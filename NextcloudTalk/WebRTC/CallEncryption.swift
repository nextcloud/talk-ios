//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Port of spreed src/utils/e2ee/encryption.js, so keys can be exchanged with the web client.
//

import Foundation
import OLMKit
import Security
import WebRTC

// Exchanges the frame keys of a call with every other session in the room. Each participant sends its own
// random key to everyone else, encrypted with a one-to-one Olm session over signaling, so the signaling
// server and the MCU never see it. Thread safe.
final class CallEncryption {

    typealias SendMessage = (_ sessionId: String, _ payload: [String: Any]) -> Void

    // Our own key, used for all our senders
    let ownKeyRing = RTCTalkKeyRing()

    private enum MessageType: String {
        case start = "encryption.start"
        case finish = "encryption.finish"
        case setKey = "encryption.setkey"
        case gotKey = "encryption.gotkey"
        case error = "encryption.error"
    }

    private struct SessionData {
        var session: OLMSession?
        var startMessageId: String?
        var lastKey: Data?
    }

    private struct PendingRequest {
        let timeout: DispatchWorkItem
        let completion: () -> Void
    }

    private let debouncePeriod: TimeInterval
    private let requestTimeout: TimeInterval

    private let queue = DispatchQueue(label: "com.nextcloud.Talk.CallEncryption")
    private let ownSessionId: String
    private let sendMessage: SendMessage

    private let account: OLMAccount
    private let identityKey: String

    private var key: Data
    private var keyIndex: UInt32 = 0
    private var isRotating = false
    private var ratchetWorkItem: DispatchWorkItem?
    private var rotateWorkItem: DispatchWorkItem?
    private var isClosed = false

    private var sessions = [String: SessionData]()
    private var pendingRequests = [String: PendingRequest]()

    // Read from WebRTC threads when receivers are created, so guarded by a lock instead of the queue
    private let remoteKeyRingsLock = NSLock()
    private var remoteKeyRings = [String: RTCTalkKeyRing]()

    // The default periods are the web client's, tests use shorter ones
    init?(ownSessionId: String, debouncePeriod: TimeInterval = 5, requestTimeout: TimeInterval = 5, sendMessage: @escaping SendMessage) {
        // OLMKit has no nullability annotations, so this compiles whether the init is imported as failable or not
        let newAccount: OLMAccount? = OLMAccount(newAccount: ())

        guard let account = newAccount,
              let identityKey = account.identityKeys()?["curve25519"] as? String
        else {
            NCLog.log("CallEncryption: Unable to create Olm account")
            return nil
        }

        self.ownSessionId = ownSessionId
        self.debouncePeriod = debouncePeriod
        self.requestTimeout = requestTimeout
        self.sendMessage = sendMessage
        self.account = account
        self.identityKey = identityKey
        self.key = Self.generateKey()

        ownKeyRing.setKey(key, at: keyIndex)
    }

    // MARK: - Public

    // The keys of a remote participant, used by the decryptors of all its streams
    func keyRing(forSessionId sessionId: String) -> RTCTalkKeyRing {
        remoteKeyRingsLock.lock()
        defer { remoteKeyRingsLock.unlock() }

        if let keyRing = remoteKeyRings[sessionId] {
            return keyRing
        }

        let keyRing = RTCTalkKeyRing()
        remoteKeyRings[sessionId] = keyRing
        return keyRing
    }

    func usersJoined(_ sessionIds: [String]) {
        queue.async {
            guard !self.isClosed else { return }

            // Of every pair of sessions, the one with the higher id starts the Olm session, compared like
            // JavaScript compares strings
            for sessionId in sessionIds where sessionId.utf16.lexicographicallyPrecedes(self.ownSessionId.utf16) {
                self.startSession(with: sessionId)
            }

            // A ratcheted key keeps new participants from decrypting what was sent before they joined, while
            // everyone else follows by ratcheting on their own
            self.ratchetWorkItem = self.debounce(self.ratchetWorkItem) { $0.ratchetKey() }
        }
    }

    func usersLeft(_ sessionIds: [String]) {
        queue.async {
            guard !self.isClosed else { return }

            self.remoteKeyRingsLock.lock()
            for sessionId in sessionIds {
                self.sessions.removeValue(forKey: sessionId)
                self.remoteKeyRings.removeValue(forKey: sessionId)
            }
            self.remoteKeyRingsLock.unlock()

            // A new key keeps participants that left from decrypting what is sent from now on
            self.rotateWorkItem = self.debounce(self.rotateWorkItem) { $0.rotateKey() }
        }
    }

    func handleMessage(from sessionId: String, payload: [String: Any]) {
        queue.async {
            guard !self.isClosed,
                  let typeString = payload["type"] as? String,
                  let type = MessageType(rawValue: typeString)
            else { return }

            switch type {
            case .start:
                self.processStartSession(from: sessionId, payload: payload)
            case .finish:
                self.processFinishSession(from: sessionId, payload: payload)
            case .setKey:
                self.processSetKey(from: sessionId, payload: payload)
            case .gotKey:
                self.processGotKey(from: sessionId, payload: payload)
            case .error:
                NCLog.log("CallEncryption: Received error from \(sessionId): \(payload["error"] ?? "")")
            }
        }
    }

    static func isEncryptionMessage(_ payload: [String: Any]) -> Bool {
        guard let type = payload["type"] as? String else { return false }
        return MessageType(rawValue: type) != nil
    }

    func close() {
        queue.async {
            self.isClosed = true
            self.ratchetWorkItem?.cancel()
            self.rotateWorkItem?.cancel()
            self.ratchetWorkItem = nil
            self.rotateWorkItem = nil

            for request in self.pendingRequests.values {
                request.timeout.cancel()
            }

            self.pendingRequests = [:]
            self.sessions = [:]

            self.remoteKeyRingsLock.lock()
            self.remoteKeyRings = [:]
            self.remoteKeyRingsLock.unlock()
        }
    }

    // MARK: - Session setup

    private func startSession(with sessionId: String) {
        var sessionData = sessions[sessionId] ?? SessionData()

        guard sessionData.session == nil, sessionData.startMessageId == nil else {
            NCLog.log("CallEncryption: Session with \(sessionId) already exists or is being started")
            return
        }

        account.generateOneTimeKeys(1)

        guard let oneTimeKeys = account.oneTimeKeys()?["curve25519"] as? [String: String],
              let oneTimeKey = oneTimeKeys.values.first
        else {
            NCLog.log("CallEncryption: No one-time key created")
            return
        }

        account.markOneTimeKeysAsPublished()

        let messageId = UUID().uuidString.lowercased()
        sessionData.startMessageId = messageId
        sessions[sessionId] = sessionData

        addRequest(messageId, onTimeout: {
            NCLog.log("CallEncryption: Starting session with \(sessionId) timed out")
            self.sessions[sessionId]?.startMessageId = nil
        })

        sendMessage(sessionId, [
            "id": messageId,
            "type": MessageType.start.rawValue,
            "identity": identityKey,
            "key": oneTimeKey
        ])
    }

    // The other side started a session, the one creating it from the start message is the "outbound" side in Olm terms
    private func processStartSession(from sessionId: String, payload: [String: Any]) {
        guard sessions[sessionId]?.session == nil else {
            NCLog.log("CallEncryption: Already has a session with \(sessionId)")
            sendError(to: sessionId, error: "Session already created")
            return
        }

        guard let messageId = payload["id"] as? String,
              let theirIdentityKey = payload["identity"] as? String,
              let theirOneTimeKey = payload["key"] as? String,
              let session = try? OLMSession(outboundSessionWith: account, theirIdentityKey: theirIdentityKey, theirOneTimeKey: theirOneTimeKey),
              let encryptedKey = encryptKey(with: session)
        else {
            NCLog.log("CallEncryption: Invalid start message from \(sessionId)")
            return
        }

        sessions[sessionId, default: SessionData()].session = session
        NCLog.log("CallEncryption: Created outbound Olm session with \(sessionId)")

        sendMessage(sessionId, [
            "id": messageId,
            "type": MessageType.finish.rawValue,
            "key": encryptedKey
        ])
    }

    private func processFinishSession(from sessionId: String, payload: [String: Any]) {
        guard sessions[sessionId]?.session == nil else {
            NCLog.log("CallEncryption: Already has a session with \(sessionId)")
            sendError(to: sessionId, error: "Session already created")
            return
        }

        guard let messageId = payload["id"] as? String, messageId == sessions[sessionId]?.startMessageId else {
            NCLog.log("CallEncryption: Received finish with wrong id from \(sessionId)")
            sendError(to: sessionId, error: "Finish has wrong id")
            return
        }

        guard let encryptedKey = payload["key"] as? [String: Any],
              let body = encryptedKey["body"] as? String,
              let session = try? OLMSession(inboundSessionWith: account, oneTimeKeyMessage: body)
        else {
            NCLog.log("CallEncryption: Invalid finish message from \(sessionId)")
            return
        }

        account.removeOneTimeKeys(for: session)

        // The finish message already carries the remote key
        let remoteKey = decryptKey(encryptedKey, with: session)

        sessions[sessionId, default: SessionData()].session = session
        sessions[sessionId]?.startMessageId = nil
        resolveRequest(messageId)

        NCLog.log("CallEncryption: Created inbound Olm session with \(sessionId)\(remoteKey == nil ? ", without a readable key" : "")")

        if let remoteKey {
            sessions[sessionId]?.lastKey = remoteKey.key
            keyRing(forSessionId: sessionId).setKey(remoteKey.key, at: remoteKey.index)
        }

        sendKey(to: sessionId, completion: {})
    }

    // MARK: - Key exchange

    private func processSetKey(from sessionId: String, payload: [String: Any]) {
        guard let session = sessions[sessionId]?.session else {
            NCLog.log("CallEncryption: No session with \(sessionId) for setting key")
            sendError(to: sessionId, error: "No session for setting key")
            return
        }

        guard let messageId = payload["id"] as? String,
              let encryptedKey = payload["key"] as? [String: Any]
        else {
            NCLog.log("CallEncryption: Invalid setkey message from \(sessionId)")
            return
        }

        guard let remoteKey = decryptKey(encryptedKey, with: session) else {
            NCLog.log("CallEncryption: Could not decrypt setkey from \(sessionId), key type \(encryptedKey["type"] ?? "")")
            return
        }

        guard let ownEncryptedKey = encryptKey(with: session) else {
            NCLog.log("CallEncryption: Could not encrypt own key for \(sessionId)")
            return
        }

        updateRemoteKey(remoteKey, forSessionId: sessionId)

        // Confirms the key, the sender waits for this before encrypting with it
        sendMessage(sessionId, [
            "id": messageId,
            "type": MessageType.gotKey.rawValue,
            "key": ownEncryptedKey
        ])
    }

    private func processGotKey(from sessionId: String, payload: [String: Any]) {
        guard let session = sessions[sessionId]?.session else {
            NCLog.log("CallEncryption: No session with \(sessionId) for confirming key")
            sendError(to: sessionId, error: "No session for confirming key")
            return
        }

        if let encryptedKey = payload["key"] as? [String: Any],
           let remoteKey = decryptKey(encryptedKey, with: session) {
            updateRemoteKey(remoteKey, forSessionId: sessionId)
        }

        if let messageId = payload["id"] as? String {
            resolveRequest(messageId)
        }
    }

    private func sendKey(to sessionId: String, completion: @escaping () -> Void) {
        guard let session = sessions[sessionId]?.session,
              let encryptedKey = encryptKey(with: session)
        else {
            completion()
            return
        }

        let messageId = UUID().uuidString.lowercased()
        addRequest(messageId, onTimeout: {
            NCLog.log("CallEncryption: Sending key to \(sessionId) timed out")
        }, completion: completion)

        sendMessage(sessionId, [
            "id": messageId,
            "type": MessageType.setKey.rawValue,
            "key": encryptedKey
        ])
    }

    private func updateRemoteKey(_ remoteKey: (key: Data, index: UInt32), forSessionId sessionId: String) {
        guard sessions[sessionId]?.lastKey != remoteKey.key else { return }

        sessions[sessionId]?.lastKey = remoteKey.key
        keyRing(forSessionId: sessionId).setKey(remoteKey.key, at: remoteKey.index)
    }

    // MARK: - Key updates

    private func ratchetKey() {
        guard !isRotating else {
            NCLog.log("CallEncryption: Not ratcheting key, currently rotating")
            return
        }

        guard let ratchetedKey = RTCTalkKeyRing.ratchetKey(key) else { return }

        // Not distributed, receivers find the ratcheted key on their own
        key = ratchetedKey
        ownKeyRing.setKey(key, at: keyIndex)
    }

    private func rotateKey() {
        isRotating = true
        key = Self.generateKey()
        keyIndex &+= 1

        let newKey = key
        let newKeyIndex = keyIndex
        let group = DispatchGroup()
        NCLog.log("CallEncryption: Rotating own key to index \(newKeyIndex)")

        for sessionId in sessions.keys {
            group.enter()
            sendKey(to: sessionId, completion: { group.leave() })
        }

        // Only encrypt with the new key once everyone has it or timed out
        group.notify(queue: queue) {
            guard !self.isClosed else { return }

            self.ownKeyRing.setKey(newKey, at: newKeyIndex)
            self.isRotating = false
        }
    }

    // MARK: - Helpers

    // The key as the web client sends it, JSON encrypted with the Olm session
    private func encryptKey(with session: OLMSession) -> [String: Any]? {
        let data: [String: Any] = ["key": key.base64EncodedString(), "index": keyIndex]

        guard let json = try? JSONSerialization.data(withJSONObject: data),
              let jsonString = String(data: json, encoding: .utf8),
              let message = try? session.encryptMessage(jsonString)
        else { return nil }

        return ["type": message.type.rawValue, "body": message.ciphertext]
    }

    private func decryptKey(_ encryptedKey: [String: Any], with session: OLMSession) -> (key: Data, index: UInt32)? {
        guard let typeValue = encryptedKey["type"] as? Int,
              let type = OLMMessageType(rawValue: typeValue),
              let body = encryptedKey["body"] as? String,
              let message = OLMMessage(ciphertext: body, type: type),
              let jsonString = try? session.decryptMessage(message),
              let json = try? JSONSerialization.jsonObject(with: Data(jsonString.utf8)) as? [String: Any],
              let keyString = json["key"] as? String,
              let key = Data(base64Encoded: keyString),
              let index = json["index"] as? Int
        else { return nil }

        return (key, UInt32(truncatingIfNeeded: index))
    }

    private func sendError(to sessionId: String, error: String) {
        sendMessage(sessionId, [
            "type": MessageType.error.rawValue,
            "error": error
        ])
    }

    private func addRequest(_ messageId: String, onTimeout: @escaping () -> Void, completion: @escaping () -> Void = {}) {
        let timeout = DispatchWorkItem {
            guard let request = self.pendingRequests.removeValue(forKey: messageId) else { return }

            onTimeout()
            request.completion()
        }

        pendingRequests[messageId] = PendingRequest(timeout: timeout, completion: completion)
        queue.asyncAfter(deadline: .now() + self.requestTimeout, execute: timeout)
    }

    private func resolveRequest(_ messageId: String) {
        guard let request = pendingRequests.removeValue(forKey: messageId) else { return }

        request.timeout.cancel()
        request.completion()
    }

    // Runs `action` once no new call came in for the debounce period, like the web client's debounce
    // The stored work item keeps its closure after running, so it must not hold self strongly
    private func debounce(_ workItem: DispatchWorkItem?, action: @escaping (CallEncryption) -> Void) -> DispatchWorkItem {
        workItem?.cancel()

        let newWorkItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isClosed else { return }
            action(self)
        }

        queue.asyncAfter(deadline: .now() + self.debouncePeriod, execute: newWorkItem)
        return newWorkItem
    }

    private static func generateKey() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Unable to generate a random key")
        return Data(bytes)
    }
}
