//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import WatchConnectivity

// The connection to Talk on the paired iPhone, which does all the work on the server
@MainActor
final class WatchConnection: NSObject, ObservableObject {

    static let shared = WatchConnection()

    @Published private(set) var snapshot: WatchSnapshot?
    // Also when the activation failed, e.g. because Talk is not installed on the iPhone
    @Published private(set) var hasFinishedActivation = false

    enum ConnectionError: LocalizedError {
        case notReachable
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notReachable:
                return NSLocalizedString("Your iPhone is not reachable", comment: "Shown on the Apple Watch")
            case .failed(let message):
                return message
            }
        }
    }

    func activate() {
        #if DEBUG
        // Example conversations and messages, to try the app without an iPhone, e.g. in the simulator
        if ProcessInfo.processInfo.arguments.contains("-TalkWatchSampleData") {
            self.snapshot = .sample
            self.hasFinishedActivation = true
            return
        }
        #endif

        guard WCSession.isSupported(), WCSession.default.activationState != .activated else { return }

        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Requests

    func refresh() async {
        // The answer comes as a new application context
        _ = try? await self.request(.refresh)
    }

    func messages(in conversation: WatchConversation) async throws -> [WatchMessage] {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-TalkWatchSampleData") {
            return WatchMessage.samples
        }
        #endif

        let reply = try await self.request(.messages, [WatchRequest.tokenKey: conversation.token])
        return WatchRequest.decode([WatchMessage].self, from: reply[WatchRequest.messagesKey] as? Data) ?? []
    }

    func send(_ text: String, to conversation: WatchConversation) async throws {
        _ = try await self.request(.send, [WatchRequest.tokenKey: conversation.token, WatchRequest.textKey: text])
    }

    func react(with reaction: String, to message: WatchMessage, in conversation: WatchConversation) async throws {
        _ = try await self.request(.react, [WatchRequest.tokenKey: conversation.token,
                                            WatchRequest.messageIdKey: NSNumber(value: message.id),
                                            WatchRequest.reactionKey: reaction])
    }

    func markAsRead(_ conversation: WatchConversation) async {
        _ = try? await self.request(.markAsRead, [WatchRequest.tokenKey: conversation.token])
    }

    private func request(_ action: WatchRequest.Action, _ parameters: [String: Any] = [:]) async throws -> [String: Any] {
        let session = WCSession.default

        guard session.activationState == .activated, session.isReachable else {
            throw ConnectionError.notReachable
        }

        var message = parameters
        message[WatchRequest.actionKey] = action.rawValue

        let reply: [String: Any] = try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(message, replyHandler: { reply in
                continuation.resume(returning: reply)
            }, errorHandler: { error in
                continuation.resume(throwing: ConnectionError.failed(error.localizedDescription))
            })
        }

        if let errorMessage = reply[WatchRequest.errorKey] as? String {
            throw ConnectionError.failed(errorMessage)
        }

        return reply
    }

    // MARK: - Snapshot

    fileprivate func applyApplicationContext(_ context: [String: Any]) {
        // An empty snapshot means no account is logged in on the iPhone
        guard let data = context[WatchRequest.snapshotKey] as? Data else {
            self.snapshot = nil
            return
        }

        if let snapshot = WatchRequest.decode(WatchSnapshot.self, from: data) {
            self.snapshot = snapshot
        }
    }
}

extension WatchConnection: WCSessionDelegate {

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext

        Task { @MainActor in
            self.hasFinishedActivation = true
            self.applyApplicationContext(context)

            if activationState == .activated {
                await self.refresh()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.applyApplicationContext(applicationContext)
        }
    }
}

#if DEBUG
extension WatchSnapshot {
    static let sample = WatchSnapshot(accountName: "Alice (cloud.example.com)", conversations: [
        WatchConversation(token: "1", displayName: "Design team", lastMessage: "Bob: The new icons look great 🎉", lastActivity: Date(),
                          unreadMessages: 3, unreadMention: true, hasCall: false, isFavorite: true, isOneToOne: false, canReact: true),
        WatchConversation(token: "2", displayName: "Carol", lastMessage: "See you at 3?", lastActivity: Date().addingTimeInterval(-600),
                          unreadMessages: 1, unreadMention: false, hasCall: false, isFavorite: true, isOneToOne: true, canReact: true),
        WatchConversation(token: "3", displayName: "Weekly sync", lastMessage: "Call started", lastActivity: Date().addingTimeInterval(-3600),
                          unreadMessages: 0, unreadMention: false, hasCall: true, isFavorite: false, isOneToOne: false, canReact: true)
    ])
}

extension WatchMessage {
    static let samples = [
        WatchMessage(id: 1, author: "Bob", text: "I pushed the new icons", date: Date().addingTimeInterval(-900), isOwnMessage: false, reactions: []),
        WatchMessage(id: 2, author: "Alice", text: "Nice, I'll have a look", date: Date().addingTimeInterval(-800), isOwnMessage: true, reactions: []),
        WatchMessage(id: 3, author: "Bob", text: "The new icons look great 🎉", date: Date().addingTimeInterval(-60), isOwnMessage: false,
                     reactions: [WatchReaction(reaction: "👍", count: 2, reactedBySelf: true)])
    ]
}
#endif
