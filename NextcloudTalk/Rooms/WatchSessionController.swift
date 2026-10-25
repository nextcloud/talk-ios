//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import WatchConnectivity

// Talk on the Apple Watch: sends the conversations of the active account to the watch and does the work on the
// server for it, see WatchModels.swift. The watch never gets any credentials.
class WatchSessionController: NSObject {

    public static let shared = WatchSessionController()

    // A snapshot in the application context needs to stay small
    private let maxConversations = 25
    private let maxPreviewLength = 120
    private let messagesLimit = 25

    private var pendingUpdate: DispatchWorkItem?
    private var lastSentSnapshot: WatchSnapshot?

    func start() {
        guard WCSession.isSupported() else { return }

        WCSession.default.delegate = self
        WCSession.default.activate()

        NotificationCenter.default.addObserver(self, selector: #selector(setNeedsUpdate), name: .NCRoomsManagerDidUpdateRooms, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setNeedsUpdate), name: .NCSettingsControllerDidChangeActiveAccount, object: nil)
    }

    private var canSendToWatch: Bool {
        let session = WCSession.default
        return session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
    }

    // Rooms are often updated several times in a row, so the update is slightly delayed to only do it once
    @objc func setNeedsUpdate() {
        DispatchQueue.main.async {
            self.pendingUpdate?.cancel()

            let update = DispatchWorkItem {
                self.sendSnapshot(force: false)
            }

            self.pendingUpdate = update
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: update)
        }
    }

    // MARK: - Snapshot

    private func currentSnapshot() -> WatchSnapshot? {
        guard NCDatabaseManager.sharedInstance().numberOfAccounts() > 0 else { return nil }

        let account = NCDatabaseManager.sharedInstance().activeAccount()
        let rooms = NCDatabaseManager.sharedInstance().roomsForAccountId(account.accountId, withRealm: nil)
            .filter { !$0.isArchived }
            .sorted { $0.lastActivity > $1.lastActivity }
            .prefix(maxConversations)

        let conversations = rooms.map { room in
            var lastMessage: String?

            // Like in notifications, sensitive conversations don't show a preview
            if !room.isSensitive, let preview = room.lastMessageString?.string {
                lastMessage = String(preview.prefix(maxPreviewLength))
            }

            return WatchConversation(token: room.token,
                                     displayName: room.displayName,
                                     lastMessage: lastMessage,
                                     lastActivity: Date(timeIntervalSince1970: TimeInterval(room.lastActivity)),
                                     unreadMessages: room.unreadMessages,
                                     unreadMention: room.unreadMention,
                                     hasCall: room.hasCall,
                                     isFavorite: room.isFavorite,
                                     isOneToOne: room.isOneToOne,
                                     canReact: room.canReact)
        }

        let serverHost = URL(string: account.server)?.host ?? account.server
        return WatchSnapshot(accountName: "\(account.userDisplayName) (\(serverHost))", conversations: Array(conversations))
    }

    private func sendSnapshot(force: Bool) {
        guard canSendToWatch else { return }

        let snapshot = self.currentSnapshot()

        guard force || snapshot != lastSentSnapshot else { return }

        var context: [String: Any] = [:]

        if let snapshot, let data = WatchRequest.encode(snapshot) {
            context[WatchRequest.snapshotKey] = data
        }

        // Makes sure the watch takes it, even if nothing changed
        context["date"] = Date().timeIntervalSince1970

        do {
            try WCSession.default.updateApplicationContext(context)
            self.lastSentSnapshot = snapshot
        } catch {
            NCLog.log("Could not send conversations to the watch: \(error.localizedDescription)")
        }
    }

    // MARK: - Requests from the watch

    private func handle(_ message: [String: Any], reply: @escaping ([String: Any]) -> Void) {
        guard let actionString = message[WatchRequest.actionKey] as? String,
              let action = WatchRequest.Action(rawValue: actionString)
        else {
            reply([WatchRequest.errorKey: "Unknown request"])
            return
        }

        guard NCDatabaseManager.sharedInstance().numberOfAccounts() > 0 else {
            reply([WatchRequest.errorKey: NSLocalizedString("Account not found", comment: "")])
            return
        }

        let account = NCDatabaseManager.sharedInstance().activeAccount()
        let token = message[WatchRequest.tokenKey] as? String ?? ""

        // The watch can wake the app up in the background, make sure the request can finish
        var backgroundTask = UIBackgroundTaskIdentifier.invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "WatchRequest") {
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }

        let finish: ([String: Any]) -> Void = { response in
            reply(response)

            DispatchQueue.main.async {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
        }

        let finishWithError: (Error?) -> Void = { error in
            if let error {
                finish([WatchRequest.errorKey: error.localizedDescription])
            } else {
                finish([:])
            }
        }

        switch action {
        case .refresh:
            self.sendSnapshot(force: true)
            NCRoomsManager.shared.updateRooms(updatingUserStatus: false, onlyLastModified: false)
            finish([:])

        case .messages:
            self.loadMessages(in: token, forAccount: account) { messages, error in
                if let messages, let data = WatchRequest.encode(messages) {
                    finish([WatchRequest.messagesKey: data])
                } else {
                    finishWithError(error)
                }
            }

        case .send:
            let text = message[WatchRequest.textKey] as? String ?? ""

            NCAPIController.sharedInstance().sendChatMessage(text, toRoom: token, threadTitle: nil, replyTo: -1, referenceId: nil,
                                                             silently: false, forAccount: account) { error in
                finishWithError(error)
                NCRoomsManager.shared.updateRooms(updatingUserStatus: false, onlyLastModified: false)
            }

        case .react:
            let messageId = (message[WatchRequest.messageIdKey] as? NSNumber)?.intValue ?? 0
            let reaction = message[WatchRequest.reactionKey] as? String ?? ""

            NCAPIController.sharedInstance().addReaction(reaction, toMessage: messageId, inRoom: token, forAccount: account) { _, error in
                finishWithError(error)
            }

        case .markAsRead:
            let lastMessageId = NCDatabaseManager.sharedInstance().room(withToken: token, forAccountId: account.accountId)?.lastMessage?.messageId ?? 0

            NCAPIController.sharedInstance().setChatReadMarker(lastMessageId, inRoom: token, forAccount: account) { error in
                finishWithError(error)
                NCRoomsManager.shared.updateRooms(updatingUserStatus: false, onlyLastModified: false)
            }
        }
    }

    private func loadMessages(in token: String, forAccount account: TalkAccount, completion: @escaping ([WatchMessage]?, Error?) -> Void) {
        let lastMessageId = NCDatabaseManager.sharedInstance().room(withToken: token, forAccountId: account.accountId)?.lastMessage?.messageId ?? 0

        _ = NCAPIController.sharedInstance().receiveChatMessages(ofRoom: token, fromLastMessageId: lastMessageId, inThread: 0, history: true,
                                                                 includeLastMessage: true, timeout: false, limit: messagesLimit,
                                                                 lastCommonReadMessage: 0, setReadMarker: false, markNotificationsAsRead: false,
                                                                 forAccount: account) { messageDicts, _, _, error, _ in
            guard let messageDicts else {
                completion(nil, error)
                return
            }

            let messages = messageDicts
                .compactMap { NCChatMessage(dictionary: $0, andAccountId: account.accountId) }
                .filter { !$0.isSystemMessage && !$0.isDeletedMessage }
                .sorted { $0.messageId < $1.messageId }
                .map { self.watchMessage(for: $0, account: account) }

            completion(messages, nil)
        }
    }

    private func watchMessage(for message: NCChatMessage, account: TalkAccount) -> WatchMessage {
        var text: String

        if message.isVoiceMessage {
            text = "🎤 " + NSLocalizedString("Voice message", comment: "")
        } else if let poll = message.poll {
            text = "📊 " + poll.name
        } else if let file = message.file() {
            text = "📎 " + file.name
        } else {
            text = message.parsedMessage()?.string ?? message.message ?? ""
        }

        let reactions = message.reactionsArray().map { reaction in
            WatchReaction(reaction: reaction.reaction, count: reaction.count, reactedBySelf: reaction.userReacted)
        }

        return WatchMessage(id: Int64(message.messageId),
                            author: message.actorDisplayName ?? "",
                            text: text,
                            date: Date(timeIntervalSince1970: TimeInterval(message.timestamp)),
                            isOwnMessage: message.actorId == account.userId && message.actorType == "users",
                            reactions: reactions)
    }
}

extension WatchSessionController: WCSessionDelegate {

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            self.setNeedsUpdate()
        }
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        // E.g. the watch app was just installed
        self.setNeedsUpdate()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Switching to another watch
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            self.handle(message, reply: replyHandler)
        }
    }
}
