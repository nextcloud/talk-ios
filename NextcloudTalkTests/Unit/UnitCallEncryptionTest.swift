//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

// Two CallEncryption instances exchange keys through a fake signaling connection
final class UnitCallEncryptionTest: XCTestCase {

    private struct Message {
        let from: String
        let to: String
        let payload: [String: Any]

        var type: String? { payload["type"] as? String }
        var keyType: Int? { (payload["key"] as? [String: Any])?["type"] as? Int }
    }

    // Delivers messages between the instances and records them
    private final class Signaling {
        private let lock = NSLock()
        private var participants = [String: CallEncryption]()
        private var messages = [Message]()
        private var waiters = [(match: (Message) -> Bool, expectation: XCTestExpectation)]()

        func sendMessage(from sessionId: String) -> CallEncryption.SendMessage {
            return { [weak self] recipient, payload in
                // Through JSON like on the wire, so only what survives it is used
                guard let self,
                      let data = try? JSONSerialization.data(withJSONObject: payload),
                      let wirePayload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return }

                let message = Message(from: sessionId, to: recipient, payload: wirePayload)

                self.lock.lock()
                self.messages.append(message)
                let receiver = self.participants[recipient]
                let fulfilled = self.waiters.filter { $0.match(message) }
                self.waiters.removeAll { waiter in fulfilled.contains { $0.expectation === waiter.expectation } }
                self.lock.unlock()

                fulfilled.forEach { $0.expectation.fulfill() }
                receiver?.handleMessage(from: sessionId, payload: wirePayload)
            }
        }

        func add(_ callEncryption: CallEncryption, forSessionId sessionId: String) {
            lock.lock()
            participants[sessionId] = callEncryption
            lock.unlock()
        }

        func expect(_ type: String, from: String, to: String) -> XCTestExpectation {
            let expectation = XCTestExpectation(description: "\(type) from \(from) to \(to)")

            lock.lock()
            waiters.append(({ $0.type == type && $0.from == from && $0.to == to }, expectation))
            lock.unlock()

            return expectation
        }

        func sent(_ type: String, from: String) -> [Message] {
            lock.lock()
            defer { lock.unlock() }
            return messages.filter { $0.type == type && $0.from == from }
        }
    }

    // "session-b" sorts after "session-a", so it starts the Olm session
    private let higherSessionId = "session-b"
    private let lowerSessionId = "session-a"

    private var signaling: Signaling!
    private var higher: CallEncryption!
    private var lower: CallEncryption!

    override func setUpWithError() throws {
        try super.setUpWithError()

        signaling = Signaling()
        higher = CallEncryption(ownSessionId: higherSessionId, debouncePeriod: 0.1, requestTimeout: 1, sendMessage: signaling.sendMessage(from: higherSessionId))
        lower = CallEncryption(ownSessionId: lowerSessionId, debouncePeriod: 0.1, requestTimeout: 1, sendMessage: signaling.sendMessage(from: lowerSessionId))
        signaling.add(higher, forSessionId: higherSessionId)
        signaling.add(lower, forSessionId: lowerSessionId)
    }

    override func tearDown() {
        higher?.close()
        lower?.close()
        super.tearDown()
    }

    // MARK: - Helper

    private func exchangeKeys() {
        let expectations = [
            signaling.expect("encryption.start", from: higherSessionId, to: lowerSessionId),
            signaling.expect("encryption.finish", from: lowerSessionId, to: higherSessionId),
            signaling.expect("encryption.setkey", from: higherSessionId, to: lowerSessionId),
            signaling.expect("encryption.gotkey", from: lowerSessionId, to: higherSessionId)
        ]

        // Both see the same join event, including their own session
        let joined = [lowerSessionId, higherSessionId]
        higher.usersJoined(joined)
        lower.usersJoined(joined)

        wait(for: expectations, timeout: TestConstants.timeoutShort, enforceOrder: true)
    }

    // MARK: - Tests

    func testHigherSessionStartsAndKeysAreExchanged() {
        exchangeKeys()

        XCTAssertTrue(signaling.sent("encryption.start", from: lowerSessionId).isEmpty)
        XCTAssertTrue(signaling.sent("encryption.error", from: lowerSessionId).isEmpty)
        XCTAssertTrue(signaling.sent("encryption.error", from: higherSessionId).isEmpty)
    }

    func testMessagesHaveWebClientFormat() throws {
        exchangeKeys()

        let start = try XCTUnwrap(signaling.sent("encryption.start", from: higherSessionId).first)
        XCTAssertNotNil(start.payload["id"] as? String)
        XCTAssertNotNil(start.payload["identity"] as? String)
        XCTAssertNotNil(start.payload["key"] as? String)

        // The side answering the start creates the outbound Olm session, so its first message is a pre-key
        // message, everything after the first reply is a normal one
        let finish = try XCTUnwrap(signaling.sent("encryption.finish", from: lowerSessionId).first)
        XCTAssertEqual(finish.payload["id"] as? String, start.payload["id"] as? String)
        XCTAssertEqual(finish.keyType, 0)

        let setKey = try XCTUnwrap(signaling.sent("encryption.setkey", from: higherSessionId).first)
        XCTAssertEqual(setKey.keyType, 1)

        let gotKey = try XCTUnwrap(signaling.sent("encryption.gotkey", from: lowerSessionId).first)
        XCTAssertEqual(gotKey.payload["id"] as? String, setKey.payload["id"] as? String)
        XCTAssertEqual(gotKey.keyType, 1)
    }

    func testDistributesNewKeyWhenSomeoneLeaves() {
        exchangeKeys()

        let setKey = signaling.expect("encryption.setkey", from: higherSessionId, to: lowerSessionId)
        let gotKey = signaling.expect("encryption.gotkey", from: lowerSessionId, to: higherSessionId)

        higher.usersLeft(["session-c"])

        wait(for: [setKey, gotKey], timeout: TestConstants.timeoutShort, enforceOrder: true)
    }

    func testRatchetsWithoutDistributingKeyWhenSomeoneJoins() {
        exchangeKeys()

        let setKey = signaling.expect("encryption.setkey", from: higherSessionId, to: lowerSessionId)
        setKey.isInverted = true

        // "session-c" sorts last, so it would start the session with us
        higher.usersJoined(["session-c"])

        wait(for: [setKey], timeout: 1)
    }

    func testAnswersKeyWithoutSessionWithError() {
        let error = signaling.expect("encryption.error", from: higherSessionId, to: "session-unknown")

        higher.handleMessage(from: "session-unknown", payload: [
            "id": "1",
            "type": "encryption.setkey",
            "key": ["type": 1, "body": "invalid"]
        ])

        wait(for: [error], timeout: TestConstants.timeoutShort)
        XCTAssertEqual(signaling.sent("encryption.error", from: higherSessionId).first?.payload["error"] as? String, "No session for setting key")
    }

    func testIsReleasedAfterClose() {
        weak var weakEncryption: CallEncryption?

        autoreleasepool {
            let encryption = CallEncryption(ownSessionId: "session-x", debouncePeriod: 0.05, requestTimeout: 1) { _, _ in }
            weakEncryption = encryption

            // A ratchet that actually ran, then a rotation that close cancels
            encryption.usersJoined(["session-x"])
            let ratcheted = expectation(description: "ratchet ran")
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { ratcheted.fulfill() }
            wait(for: [ratcheted], timeout: TestConstants.timeoutShort)

            encryption.usersLeft(["session-y"])
            encryption.close()
        }

        // Queued closures keep it alive until they ran
        let released = expectation(for: NSPredicate { _, _ in weakEncryption == nil }, evaluatedWith: nil)
        wait(for: [released], timeout: TestConstants.timeoutShort)
    }

    func testKeyRingIsKeptPerSession() {
        XCTAssertTrue(higher.keyRing(forSessionId: lowerSessionId) === higher.keyRing(forSessionId: lowerSessionId))
        XCTAssertFalse(higher.keyRing(forSessionId: lowerSessionId) === higher.keyRing(forSessionId: "session-c"))
    }

    func testRecognizesEncryptionMessages() {
        XCTAssertTrue(CallEncryption.isEncryptionMessage(["type": "encryption.start"]))
        XCTAssertTrue(CallEncryption.isEncryptionMessage(["type": "encryption.gotkey"]))
        XCTAssertFalse(CallEncryption.isEncryptionMessage(["type": "offer"]))
        XCTAssertFalse(CallEncryption.isEncryptionMessage([:]))
    }
}
