//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

public extension NSNotification.Name {
    static let NCChatControllerDidReceiveInitialChatHistory = NSNotification.Name("NCChatControllerDidReceiveInitialChatHistoryNotification")
    static let NCChatControllerDidReceiveInitialChatHistoryOffline = NSNotification.Name("NCChatControllerDidReceiveInitialChatHistoryOfflineNotification")
    static let NCChatControllerDidReceiveChatHistory = NSNotification.Name("NCChatControllerDidReceiveChatHistoryNotification")
    static let NCChatControllerDidReceiveChatMessages = NSNotification.Name("NCChatControllerDidReceiveChatMessagesNotification")
    static let NCChatControllerDidSendChatMessage = NSNotification.Name("NCChatControllerDidSendChatMessageNotification")
    static let NCChatControllerDidReceiveChatBlocked = NSNotification.Name("NCChatControllerDidReceiveChatBlockedNotification")
    static let NCChatControllerDidReceiveNewerCommonReadMessage = NSNotification.Name("NCChatControllerDidReceiveNewerCommonReadMessageNotification")
    static let NCChatControllerDidReceiveUpdateMessage = NSNotification.Name("NCChatControllerDidReceiveUpdateMessageNotification")
    static let NCChatControllerDidReceiveHistoryCleared = NSNotification.Name("NCChatControllerDidReceiveHistoryClearedNotification")
    static let NCChatControllerDidReceiveCallStartedMessage = NSNotification.Name("NCChatControllerDidReceiveCallStartedMessageNotification")
    static let NCChatControllerDidReceiveCallEndedMessage = NSNotification.Name("NCChatControllerDidReceiveCallEndedMessageNotification")
    static let NCChatControllerDidReceiveMessagesInBackground = NSNotification.Name("NCChatControllerDidReceiveMessagesInBackgroundNotification")
    static let NCChatControllerDidReceiveThreadMessage = NSNotification.Name("NCChatControllerDidReceiveThreadMessageNotification")
    static let NCChatControllerDidReceiveThreadNotFound = NSNotification.Name("NCChatControllerDidReceiveThreadNotFoundNotification")
}

public class NCChatController: NSObject {

    public var room: NCRoom
    public var threadId: Int = 0
    public var hasReceivedMessagesFromServer = false

    private let account: TalkAccount
    private var stopChatMessagesPoll = false
    private var getHistoryTask: URLSessionDataTask?
    private var pullMessagesTask: URLSessionDataTask?

    private enum ChatRelayState {
        case inactive, active, catchingUp
    }

    private var chatRelayState: ChatRelayState = .inactive
    private var chatRelayMessagesBuffer: [[String: Any]] = []
    private var chatRelayMessagesQueue: DispatchQueue?
    private var externalSignalingController: NCExternalSignalingController?

    // Debounces the read-marker requests we issue while receiving messages over the chat relay. Only accessed on the main queue.
    private var setReadMarkerWorkItem: DispatchWorkItem?

    public init!(for room: NCRoom) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: room.accountId) else { return nil }

        self.room = room
        self.account = account

        super.init()

        setupChatRelay()
        AllocationTracker.shared.addAllocation("NCChatController")
    }

    public init!(forThreadId threadId: Int, in room: NCRoom) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: room.accountId) else { return nil }

        self.room = room
        self.threadId = threadId
        self.account = account

        super.init()

        setupChatRelay()
        AllocationTracker.shared.addAllocation("NCChatController")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        AllocationTracker.shared.removeAllocation("NCChatController")
    }

    private var isThreadController: Bool {
        return threadId > 0
    }

    private func willBeVisibleMessage(_ message: NCChatMessage) -> Bool {
        // Update messages are not visible in normal chats or thread views
        if message.isUpdateMessage {
            return false
        }

        // Thread messages are not visible in normal chat views.
        if !isThreadController, message.isThreadMessage() {
            return false
        }

        // In thread controller mode we only receive thread messages,
        // so no check for non-thread messages is needed

        return true
    }

    // MARK: - Database

    private func managedSortedBlocksForRoomOrThread() -> RLMResults<AnyObject> {
        let predicate: NSPredicate
        if isThreadController {
            predicate = NSPredicate(format: "internalId = %@ AND threadId = %ld", room.internalId, threadId)
        } else {
            predicate = NSPredicate(format: "internalId = %@ AND threadId = 0", room.internalId)
        }

        return NCChatBlock.objects(with: predicate).sortedResults(usingKeyPath: "newestMessageId", ascending: true)
    }

    private func chatBlocksForRoomOrThread() -> [NCChatBlock] {
        let managedSortedBlocks = managedSortedBlocksForRoomOrThread()

        // Create an unmanaged copy of the blocks
        var sortedBlocks: [NCChatBlock] = []
        for case let managedBlock as NCChatBlock in managedSortedBlocks {
            sortedBlocks.append(NCChatBlock(value: managedBlock))
        }

        return sortedBlocks
    }

    private func getBatchOfMessages(inBlock chatBlock: NCChatBlock?, fromMessageId messageId: Int, included: Bool, ensureIncludesMessageId ensuredMessageId: Int) -> [NCChatMessage] {
        let blockOldest = chatBlock?.oldestMessageId ?? 0
        let blockNewest = chatBlock?.newestMessageId ?? 0
        let fromMessageId = messageId > 0 ? messageId : blockNewest

        let query: NSPredicate
        if isThreadController {
            if included {
                query = NSPredicate(format: "accountId = %@ AND token = %@ AND threadId = %ld AND messageId >= %ld AND messageId <= %ld", account.accountId, room.token, threadId, blockOldest, fromMessageId)
            } else {
                query = NSPredicate(format: "accountId = %@ AND token = %@ AND threadId = %ld AND messageId >= %ld AND messageId < %ld", account.accountId, room.token, threadId, blockOldest, fromMessageId)
            }
        } else {
            if included {
                query = NSPredicate(format: "accountId = %@ AND token = %@ AND messageId >= %ld AND messageId <= %ld", account.accountId, room.token, blockOldest, fromMessageId)
            } else {
                query = NSPredicate(format: "accountId = %@ AND token = %@ AND messageId >= %ld AND messageId < %ld", account.accountId, room.token, blockOldest, fromMessageId)
            }
        }

        let managedSortedMessages = NCChatMessage.objects(with: query).sortedResults(usingKeyPath: "messageId", ascending: true)

        // Create an unmanaged copy of the messages
        var sortedMessages: [NCChatMessage] = []
        var numberOfStoredVisibleMessages = 0

        // When there's no message we need to ensure being included, we just assume it's included to enforce the default limit
        var reachedEnsuredMessageId = ensuredMessageId <= 0

        // Iterate backwards and check if we gathered enough visible messages (or more, if we need to include the unread marker)
        var index = Int(managedSortedMessages.count) - 1
        while index >= 0 {
            guard let managedMessage = managedSortedMessages.object(at: UInt(index)) as? NCChatMessage else {
                index -= 1
                continue
            }

            let sortedMessage = NCChatMessage(value: managedMessage)

            // Since we iterate backwards, insert the object at the beginning of the array to keep it sorted
            sortedMessages.insert(sortedMessage, at: 0)

            if sortedMessage.messageId == ensuredMessageId {
                reachedEnsuredMessageId = true
            }

            // We only count visible messages and we only count, if we already found the message that we need to ensure
            if reachedEnsuredMessageId, willBeVisibleMessage(sortedMessage) {
                numberOfStoredVisibleMessages += 1
            }

            // Break in case we found the ensured message and we hit the visible message limit
            if reachedEnsuredMessageId, numberOfStoredVisibleMessages >= NCAPIController.shared.kReceivedChatMessagesLimit {
                break
            }

            index -= 1
        }

        NSLog("Returning batch of %ld messages", sortedMessages.count)

        return sortedMessages
    }

    private func getNewStoredMessages(inBlock chatBlock: NCChatBlock?, sinceMessageId messageId: Int) -> [NCChatMessage] {
        let blockNewest = chatBlock?.newestMessageId ?? 0

        let query: NSPredicate
        if isThreadController {
            query = NSPredicate(format: "accountId = %@ AND token = %@ AND threadId = %ld AND messageId > %ld AND messageId <= %ld", account.accountId, room.token, threadId, messageId, blockNewest)
        } else {
            query = NSPredicate(format: "accountId = %@ AND token = %@ AND messageId > %ld AND messageId <= %ld AND (isThread == 0 OR threadId == 0 OR threadId == messageId)", account.accountId, room.token, messageId, blockNewest)
        }

        let managedSortedMessages = NCChatMessage.objects(with: query).sortedResults(usingKeyPath: "messageId", ascending: true)

        // Create an unmanaged copy of the messages
        var sortedMessages: [NCChatMessage] = []
        for case let managedMessage as NCChatMessage in managedSortedMessages {
            sortedMessages.append(NCChatMessage(value: managedMessage))
        }

        return sortedMessages
    }

    public func storeMessages(_ messages: [[AnyHashable: Any]], with realm: RLMRealm) {
        // Add or update messages
        for messageDict in messages {
            // messageWithDictionary takes care of setting a potential available parentId
            guard let message = NCChatMessage(dictionary: messageDict, andAccountId: account.accountId) else { continue }

            if let referenceId = message.referenceId, !referenceId.isEmpty {
                if let managedTemporaryMessage = NCChatMessage.objects(where: "referenceId = %@ AND isTemporary = true", referenceId).firstObject() as? NCChatMessage {
                    realm.delete(managedTemporaryMessage)
                }
            }

            if let managedMessage = NCChatMessage.objects(where: "internalId = %@", message.internalId ?? "").firstObject() as? NCChatMessage {
                NCChatMessage.update(managedMessage, with: message, isRoomLastMessage: false)
            } else {
                realm.add(message)
            }

            if message.isThreadCreatedMessage {
                if let thread = NCThread.createThread(from: message, andAccountId: message.accountId ?? account.accountId) {
                    realm.add(thread)
                }
            } else if message.isThreadMessage() {
                NCThread.updateThread(withThreadMessage: message)
            }

            let parentDict = messageDict["parent"] as? [AnyHashable: Any]
            if let parent = NCChatMessage(dictionary: parentDict, andAccountId: account.accountId) {
                if let managedParentMessage = NCChatMessage.objects(where: "internalId = %@", parent.internalId ?? "").firstObject() as? NCChatMessage {
                    // updateChatMessage takes care of not setting a parentId to nil if there was one before
                    NCChatMessage.update(managedParentMessage, with: parent, isRoomLastMessage: false)
                } else {
                    realm.add(parent)
                }
            }
        }
    }

    private func storeMessages(_ messages: [[String: Any]]) {
        let realm = RLMRealm.default()
        try? realm.transaction {
            self.storeMessages(messages.map { $0 as [AnyHashable: Any] }, with: realm)
        }
    }

    public func hasOlderStoredMessagesThanMessageId(_ messageId: Int) -> Bool {
        let query = NSPredicate(format: "accountId = %@ AND token = %@ AND messageId < %ld", account.accountId, room.token, messageId)
        return NCChatMessage.objects(with: query).count > 0
    }

    private func removeAllStoredMessagesAndChatBlocks() {
        let realm = RLMRealm.default()
        try? realm.transaction {
            let query = NSPredicate(format: "accountId = %@ AND token = %@", self.account.accountId, self.room.token)
            realm.deleteObjects(NCChatMessage.objects(with: query))
            realm.deleteObjects(NCChatBlock.objects(with: query))
            let threadsQuery = NSPredicate(format: "accountId = %@ AND roomToken = %@", self.account.accountId, self.room.token)
            realm.deleteObjects(NCThread.objects(with: threadsQuery))
        }
    }

    public func removeExpiredMessages() {
        let realm = RLMRealm.default()
        let currentTimestamp = Int(Date().timeIntervalSince1970)
        try? realm.transaction {
            let query = NSPredicate(format: "accountId = %@ AND token = %@ AND expirationTimestamp > 0 AND expirationTimestamp <= %ld", self.account.accountId, self.room.token, currentTimestamp)
            realm.deleteObjects(NCChatMessage.objects(with: query))
        }
    }

    private func updateLastChatBlock(withNewestKnown newestKnown: Int) {
        let realm = RLMRealm.default()
        try? realm.transaction {
            let managedSortedBlocks = self.managedSortedBlocksForRoomOrThread()
            let lastBlock = managedSortedBlocks.lastObject() as? NCChatBlock
            if newestKnown > 0 {
                lastBlock?.newestMessageId = newestKnown
            }
        }
    }

    private func updateChatBlocks(withLastKnown lastKnown: Int) {
        if lastKnown <= 0 {
            return
        }

        // Safety check: prevent storing a messageId older than the thread's first message as block's oldestMessageId when in a thread controller
        let oldestMessageKnown = (isThreadController && lastKnown < threadId) ? threadId : lastKnown

        let realm = RLMRealm.default()
        try? realm.transaction {
            let managedSortedBlocks = self.managedSortedBlocksForRoomOrThread()
            guard let lastBlock = managedSortedBlocks.lastObject() as? NCChatBlock else { return }

            let count = Int(managedSortedBlocks.count)
            // There is more than one chat block stored
            if count > 1 {
                var index = count - 2
                while index >= 0 {
                    guard let block = managedSortedBlocks.object(at: UInt(index)) as? NCChatBlock else {
                        index -= 1
                        continue
                    }

                    // Merge blocks if the lastKnown message is inside the current block
                    if lastKnown >= block.oldestMessageId, lastKnown <= block.newestMessageId {
                        lastBlock.oldestMessageId = block.oldestMessageId
                        realm.delete(block)
                        break
                    // Update lastBlock if the lastKnown message is between the 2 blocks
                    } else if lastKnown > block.newestMessageId {
                        lastBlock.oldestMessageId = oldestMessageKnown
                        break
                    // The current block is completely included in the retrieved history
                    // This could happen if we vary the message limit when fetching messages
                    // Delete included block
                    } else if lastKnown < block.oldestMessageId {
                        realm.delete(block)
                    }

                    index -= 1
                }
            // There is just one chat block stored
            } else {
                lastBlock.oldestMessageId = oldestMessageKnown
            }
        }
    }

    private func updateChatBlocks(withReceivedMessages messages: [[String: Any]]?, newestKnown: Int, andLastKnown lastKnown: Int) {
        let sortedMessages = sortedMessages(fromMessageArray: messages)
        let newestMessageReceived = sortedMessages.last
        let newestMessageKnown = newestKnown > 0 ? newestKnown : (newestMessageReceived?.messageId ?? 0)
        // Safety check: prevent storing a messageId older than the thread's first message as block's oldestMessageId when in a thread controller
        let oldestMessageKnown = (isThreadController && lastKnown < threadId) ? threadId : lastKnown

        let realm = RLMRealm.default()
        try? realm.transaction {
            let managedSortedBlocks = self.managedSortedBlocksForRoomOrThread()

            // Create new chat block
            let newBlock = NCChatBlock()
            newBlock.internalId = self.room.internalId
            newBlock.accountId = self.room.accountId
            newBlock.token = self.room.token
            newBlock.threadId = self.threadId
            newBlock.oldestMessageId = oldestMessageKnown
            newBlock.newestMessageId = newestMessageKnown
            newBlock.hasHistory = true

            let count = Int(managedSortedBlocks.count)
            // There is at least one chat block stored
            if count > 0 {
                var index = count - 1
                while index >= 0 {
                    guard let block = managedSortedBlocks.object(at: UInt(index)) as? NCChatBlock else {
                        index -= 1
                        continue
                    }

                    // Merge blocks if the lastKnown message is inside the current block
                    if lastKnown >= block.oldestMessageId, lastKnown <= block.newestMessageId {
                        block.newestMessageId = newestMessageKnown
                        break
                    // Add new block if it didn't reach the previous block
                    } else if lastKnown > block.newestMessageId {
                        realm.add(newBlock)
                        break
                    // The current block is completely included in the retrieved history
                    // This could happen if we vary the message limit when fetching messages
                    // Delete included block
                    } else if lastKnown < block.oldestMessageId {
                        realm.delete(block)
                    }

                    index -= 1
                }
            // No chat blocks stored yet, add new chat block
            } else {
                realm.add(newBlock)
            }
        }
    }

    private func updateHistoryFlagInFirstBlock() {
        let realm = RLMRealm.default()
        try? realm.transaction {
            let managedSortedBlocks = self.managedSortedBlocksForRoomOrThread()
            let firstChatBlock = managedSortedBlocks.firstObject() as? NCChatBlock
            firstChatBlock?.hasHistory = false
        }
    }

    private func transactionForMessage(withReferenceId referenceId: String, block: @escaping (_ message: NCChatMessage?) -> Void) {
        let realm = RLMRealm.default()
        try? realm.transaction {
            let managedChatMessage = NCChatMessage.objects(where: "referenceId = %@ AND isTemporary = true", referenceId).firstObject() as? NCChatMessage
            block(managedChatMessage)
        }
    }

    private func sortedMessages(fromMessageArray messages: [[String: Any]]?) -> [NCChatMessage] {
        guard let messages else { return [] }

        var sortedMessages: [NCChatMessage] = []
        sortedMessages.reserveCapacity(messages.count)
        for messageDict in messages {
            if let message = NCChatMessage(dictionary: messageDict as [AnyHashable: Any]) {
                sortedMessages.append(message)
            }
        }

        // Sort by messageId
        sortedMessages.sort { $0.messageId < $1.messageId }

        return sortedMessages
    }

    // MARK: - External Signaling / Chat Relay

    private func setupChatRelay() {
        guard let signalingController = NCSettingsController.sharedInstance().externalSignalingController(forAccountId: account.accountId),
              signalingController.hasChatRelay else { return }
        externalSignalingController = signalingController
        chatRelayMessagesQueue = DispatchQueue(label: "chat.relay.message.queue")
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveChatMessageFromExternalSignaling(_:)), name: .extSignalingDidReceiveChatMessage, object: signalingController)
        NotificationCenter.default.addObserver(self, selector: #selector(didReconnectExternalSignaling(_:)), name: .extSignalingDidReconnect, object: signalingController)
    }

    @objc private func didReceiveChatMessageFromExternalSignaling(_ notification: Notification) {
        guard let roomToken = notification.userInfo?["roomToken"] as? String, roomToken == room.token,
              let messageDict = notification.userInfo?["message"] as? [String: Any] else { return }

        chatRelayMessagesQueue?.async {
            if self.chatRelayState != .active {
                self.chatRelayMessagesBuffer.append(messageDict)
                return
            }
            self.handleChatRelayMessage(messageDict)
        }
    }

    private func startProcessingChatRelayMessages() {
        chatRelayMessagesQueue?.async {
            self.chatRelayState = .active
            self.flushChatRelayMessagesBuffer()
        }
    }

    private func flushChatRelayMessagesBuffer() {
        guard !chatRelayMessagesBuffer.isEmpty else { return }

        chatRelayMessagesBuffer.sort { ($0["id"] as? Int ?? 0) < ($1["id"] as? Int ?? 0) }

        // Snapshot and clear first so messages arriving meanwhile aren't lost.
        let bufferedMessages = chatRelayMessagesBuffer
        chatRelayMessagesBuffer.removeAll()

        for messageDict in bufferedMessages {
            handleChatRelayMessage(messageDict)
        }
    }

    // Falls back to a chat API catch-up when a chat relay message can't be reliably rendered from its
    // payload (file/object shares, call_ended, unknown system messages). Incoming chat relay messages
    // are buffered while the catch-up runs.
    private func triggerChatRelayCatchUp() {
        guard chatRelayState != .catchingUp else { return }

        chatRelayState = .catchingUp

        let lastChatBlock = chatBlocksForRoomOrThread().last
        let fromMessageId = lastChatBlock?.newestMessageId ?? 0
        DispatchQueue.main.async {
            self.startReceivingChatMessages(fromMessagesId: fromMessageId, withTimeout: false)
        }
    }

    private func handleChatRelayMessage(_ messageDict: [String: Any]) {
        guard let message = NCChatMessage(dictionary: messageDict as [AnyHashable: Any], andAccountId: account.accountId) else {
            print("Could not parse a message received over the chat relay, catching up over the chat API")
            triggerChatRelayCatchUp()
            return
        }

        if isThreadController, message.threadId != threadId {
            return
        }

        // The backend used to send an incorrect messageId for reaction_revoked system messages, so
        // we catch up over the chat API instead of rendering them from the relay payload. This is
        // fixed server-side in https://github.com/nextcloud/spreed/pull/18363, so we can remove this
        // check after some time, once users have had a chance to upgrade their instances.
        if message.systemMessage == "reaction_revoked" {
            triggerChatRelayCatchUp()
            return
        }

        let lastChatBlock = chatBlocksForRoomOrThread().last
        let lastNewestMessageId = lastChatBlock?.newestMessageId ?? 0

        if message.messageId <= lastNewestMessageId {
            return
        }

        if message.systemMessage == "reaction" || message.systemMessage == "reaction_revoked" || message.systemMessage == "reaction_deleted" {
            handleReactionRelayMessage(message, withDict: messageDict, lastNewestMessageId: lastNewestMessageId)
            return
        }

        guard let storableMessageDict = storableDict(forChatRelayMessage: message, withDict: messageDict) else {
            triggerChatRelayCatchUp()
            return
        }

        storeRelayMessage(message, storableDict: storableMessageDict, lastNewestMessageId: lastNewestMessageId)

        print("Stored a new message received over the chat relay")
    }

    // Stores a message received over the chat relay and advances the read marker. Both the regular and
    // the reaction relay paths funnel through here so the chat block, the stored message, the new-message
    // notification and the read marker stay in sync.
    private func storeRelayMessage(_ message: NCChatMessage, storableDict: [String: Any], lastNewestMessageId: Int) {
        updateLastChatBlock(withNewestKnown: message.messageId)
        storeMessages([storableDict])
        checkForNewMessages(fromMessageId: lastNewestMessageId)

        // We only reach this point while the chat relay is active (these methods are only called in the
        // `.active` state), which is the relay equivalent of polling the chat API with setReadMarker
        // enabled. Since relay messages are not fetched over the chat API, the read marker is no longer
        // advanced as a side effect, so we have to set it explicitly to keep the same behaviour.
        setChatRelayReadMarker(toMessageId: message.messageId)
    }

    // Marks the newest message received over the chat relay as read on the server. Requests are
    // debounced so a burst of relay messages (e.g. while flushing the buffer after catching up)
    // results in a single /read request for the newest message.
    private func setChatRelayReadMarker(toMessageId messageId: Int) {
        DispatchQueue.main.async {
            self.setReadMarkerWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }

                NCAPIController.sharedInstance().setChatReadMarker(messageId, inRoom: self.room.token, forAccount: self.account) { error in
                    guard error == nil else { return }

                    // Keep our local room in sync so the unread indicators stay correct
                    NCRoomsManager.shared.updateLastReadMessage(messageId, forRoom: self.room)
                }
            }

            self.setReadMarkerWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: workItem)
        }
    }

    // Returns the dictionary to store for a chat relay message, or nil if it must be fetched over the chat API.
    private func storableDict(forChatRelayMessage message: NCChatMessage, withDict messageDict: [String: Any]) -> [String: Any]? {
        // Messages with file/object attachments carry parameters that don't match the chat API response
        // (e.g. file path and link), so they always need to be fetched over the chat API.
        if message.file() != nil {
            print("A message received over the chat relay has a file attachment, fetching it from the chat API instead")
            return nil
        }

        // System messages are not localized in the chat relay payload, so we localize them on the client.
        if message.isSystemMessage {
            let silentCall = ((messageDict["call"] as? [String: Any])?["silent"] as? Bool) ?? false
            guard let localizedMessage = NCSystemMessageLocalizer.localizedSystemMessage(for: message, in: room, account: account, silentCall: silentCall) else {
                print("System message '\(message.systemMessage ?? "")' received over the chat relay can't be localized on the client, fetching it from the chat API instead")
                return nil
            }
            var localizedMessageDict = messageDict
            localizedMessageDict["message"] = localizedMessage
            return localizedMessageDict
        }

        return messageDict
    }

    // Handles reaction system messages received via the chat relay. The relay broadcasts reactionsSelf
    // from the actor's perspective (not per-user), so we replace it with the correct value computed
    // from the current DB state plus the self-actor delta before passing to storeMessages — mirroring
    // the web's fromRealtime reactionsSelf computation in messagesStore.js (PR #16349).
    private func handleReactionRelayMessage(_ message: NCChatMessage, withDict messageDict: [String: Any], lastNewestMessageId: Int) {
        var storableDict = messageDict

        if var parentDict = messageDict["parent"] as? [String: Any] {
            var selfReactions: [String] = []
            if let parentId = message.parentId,
               let parentInDB = NCChatMessage.objects(where: "internalId = %@", parentId).firstObject() as? NCChatMessage,
               let jsonString = parentInDB.reactionsSelfJSONString, !jsonString.isEmpty,
               let data = jsonString.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String] {
                selfReactions = parsed
            }

            if message.isMessage(from: account.userId), let emoji = message.message, !emoji.isEmpty {
                if message.systemMessage == "reaction" && !selfReactions.contains(emoji) {
                    selfReactions.append(emoji)
                } else if message.systemMessage == "reaction_revoked" {
                    selfReactions.removeAll { $0 == emoji }
                }
            }

            parentDict["reactionsSelf"] = selfReactions
            storableDict["parent"] = parentDict
        }

        storeRelayMessage(message, storableDict: storableDict, lastNewestMessageId: lastNewestMessageId)
    }

    @objc private func didReconnectExternalSignaling(_ notification: Notification) {
        guard !stopChatMessagesPoll, externalSignalingController?.hasChatRelay == true else { return }

        let sessionChanged = notification.userInfo?["sessionChanged"] as? Bool ?? false
        guard sessionChanged else { return }

        print("Signaling session was not resumed, catching up on any missed messages over the chat API")

        chatRelayMessagesQueue?.async {
            self.triggerChatRelayCatchUp()
        }
    }

    // MARK: - Chat

    public func getTemporaryMessages() -> [NCChatMessage] {
        let query = NSPredicate(format: "accountId = %@ AND token = %@ AND isTemporary = true", account.accountId, room.token)
        let managedTemporaryMessages = NCChatMessage.objects(with: query)
        let managedSortedTemporaryMessages = managedTemporaryMessages.sortedResults(usingKeyPath: "timestamp", ascending: true)

        // Mark temporary messages sent more than 12 hours ago as failed-to-send messages
        let twelveHoursAgoTimestamp = Int(Date().timeIntervalSince1970) - (60 * 60 * 12)

        for case let temporaryMessage as NCChatMessage in managedTemporaryMessages where temporaryMessage.timestamp < twelveHoursAgoTimestamp {
            let realm = RLMRealm.default()
            try? realm.transaction {
                temporaryMessage.isOfflineMessage = false
                temporaryMessage.sendingFailed = true
            }
        }

        // Create an unmanaged copy of the messages
        var sortedMessages: [NCChatMessage] = []
        for case let managedMessage as NCChatMessage in managedSortedTemporaryMessages {
            sortedMessages.append(NCChatMessage(value: managedMessage))
        }

        return sortedMessages
    }

    public func updateHistoryInBackground(completion: ((_ error: OcsError?) -> Void)?) {
        // If there's a pull task running right now, we should not interfere with that
        if let pullMessagesTask, pullMessagesTask.state == .running {
            completion?(OcsError(withError: NSError(domain: NSCocoaErrorDomain, code: 0), withTask: nil))
            return
        }

        let lastChatBlock = chatBlocksForRoomOrThread().last
        var expired = false

        let bgTask = BGTaskHelper.startBackgroundTask(withName: "updateHistoryInBackgroundWithCompletionBlock") { _ in
            NCLog.log("ExpirationHandler called updateHistoryInBackgroundWithCompletionBlock")
            expired = true

            // Make sure we actually end a running pullMessagesTask, because otherwise the completion handler might not be called in time
            self.pullMessagesTask?.cancel()
        }

        pullMessagesTask = NCAPIController.sharedInstance().receiveChatMessages(ofRoom: room.token, fromLastMessageId: lastChatBlock?.newestMessageId ?? 0, inThread: threadId, history: false, includeLastMessage: false, timeout: false, limit: NCAPIController.shared.kReceivedChatMessagesLimit, lastCommonReadMessage: room.lastCommonReadMessage, setReadMarker: false, markNotificationsAsRead: false, forAccount: account) { messages, lastKnownMessage, lastCommonReadMessage, error, _ in
            if expired {
                completion?(error)
                bgTask.stopBackgroundTask()
                return
            }

            if let error {
                NSLog("Could not get background chat history. Error: \(error.description)")
            } else {
                // Update chat blocks
                self.updateLastChatBlock(withNewestKnown: lastKnownMessage)

                // Store new messages
                if let messages, !messages.isEmpty {
                    // In case we finish after the app already got active again, notify any potential view controller
                    var userInfo: [AnyHashable: Any] = [:]
                    userInfo["room"] = self.room.token

                    for messageDict in messages {
                        let message = NCChatMessage(dictionary: messageDict as [AnyHashable: Any], andAccountId: self.account.accountId)

                        if message?.systemMessage == "history_cleared" {
                            self.clearHistoryAndResetChatController()

                            userInfo["historyCleared"] = message
                            NotificationCenter.default.post(name: .NCChatControllerDidReceiveHistoryCleared, object: self, userInfo: userInfo)
                            return
                        }
                    }

                    self.storeMessages(messages)
                    self.checkLastCommonReadMessage(lastCommonReadMessage)

                    NotificationCenter.default.post(name: .NCChatControllerDidReceiveMessagesInBackground, object: self, userInfo: userInfo)
                }
            }

            completion?(error)

            bgTask.stopBackgroundTask()
        }
    }

    public func checkForNewMessages(fromMessageId messageId: Int) {
        let lastChatBlock = chatBlocksForRoomOrThread().last
        let storedMessages = getNewStoredMessages(inBlock: lastChatBlock, sinceMessageId: messageId)

        guard !storedMessages.isEmpty else { return }

        // We still get the new messages from the queue of the caller, so the lookup stays ordered
        // with the stores (relay messages are stored on chat.relay.message.queue and looking them
        // up on main could race with later stores and post duplicates). The notifications should
        // be posted on the main thread since the observers perform UI work.
        if Thread.isMainThread {
            notify(forNewMessages: storedMessages)
        } else {
            DispatchQueue.main.async {
                self.notify(forNewMessages: storedMessages)
            }
        }
    }

    private func notify(forNewMessages storedMessages: [NCChatMessage]) {
        var userInfo: [AnyHashable: Any] = [:]
        userInfo["room"] = room.token

        for message in storedMessages {
            // Notify if "call started" have been received
            if message.systemMessage == "call_started" {
                NotificationCenter.default.post(name: .NCChatControllerDidReceiveCallStartedMessage, object: self, userInfo: userInfo)
            }
            // Notify if "call ended" have been received
            if message.systemMessage == "call_ended" ||
                message.systemMessage == "call_ended_everyone" ||
                message.systemMessage == "call_missed" ||
                message.systemMessage == "call_tried" {
                NotificationCenter.default.post(name: .NCChatControllerDidReceiveCallEndedMessage, object: self, userInfo: userInfo)
            }
            // Notify if an "update message" has been received
            if message.isUpdateMessage || message.isVisibleUpdateMessage {
                userInfo["updateMessage"] = message
                NotificationCenter.default.post(name: .NCChatControllerDidReceiveUpdateMessage, object: self, userInfo: userInfo)
            }
            // Notify if a "thread message" has been received
            if message.isThreadMessage() {
                userInfo["threadMessage"] = message
                NotificationCenter.default.post(name: .NCChatControllerDidReceiveThreadMessage, object: self, userInfo: userInfo)
            }
            // Notify if "history cleared" has been received
            if message.systemMessage == "history_cleared" {
                userInfo["historyCleared"] = message
                NotificationCenter.default.post(name: .NCChatControllerDidReceiveHistoryCleared, object: self, userInfo: userInfo)
                return
            }
        }

        userInfo["messages"] = storedMessages
        userInfo["firstNewMessagesAfterHistory"] = !hasReceivedMessagesFromServer
        NotificationCenter.default.post(name: .NCChatControllerDidReceiveChatMessages, object: self, userInfo: userInfo)

        updateLastMessageIfNeeded(fromMessages: storedMessages)
    }

    private func updateLastMessageIfNeeded(fromMessages storedMessages: [NCChatMessage]) {
        // Try to find the last non-update message - Messages are already sorted by messageId here
        var lastNonUpdateMessage: NCChatMessage?
        let lastMessage = storedMessages.last

        var index = storedMessages.count - 1
        while index >= 0 {
            let tempMessage = storedMessages[index]
            if !tempMessage.isUpdateMessage {
                lastNonUpdateMessage = tempMessage
                break
            }
            index -= 1
        }

        // Make sure we update the unread flags for the room (lastMessage can already be set, but there still might be unread flags)
        if let lastMessage, lastMessage.timestamp >= self.room.lastActivity {
            // Make sure our local reference to the room also has the correct lastActivity set
            if let lastNonUpdateMessage {
                self.room.lastActivity = lastNonUpdateMessage.timestamp
            }

            // We always want to set the room to have no unread messages, optionally we also want to update the last message, if there's one
            NCRoomsManager.shared.setNoUnreadMessages(forRoom: self.room, withLastMessage: lastNonUpdateMessage)
        }
    }

    public func getInitialChatHistoryForOfflineMode() {
        var userInfo: [AnyHashable: Any] = [:]
        userInfo["room"] = room.token

        var lastReadMessageId = 0
        if NCDatabaseManager.sharedInstance().roomHasTalkCapability(.chatReadMarker, for: room) {
            lastReadMessageId = room.lastReadMessage
        }

        let lastChatBlock = chatBlocksForRoomOrThread().last
        let storedMessages = getBatchOfMessages(inBlock: lastChatBlock, fromMessageId: lastChatBlock?.newestMessageId ?? 0, included: true, ensureIncludesMessageId: lastReadMessageId)
        userInfo["messages"] = storedMessages
        NotificationCenter.default.post(name: .NCChatControllerDidReceiveInitialChatHistoryOffline, object: self, userInfo: userInfo)
    }

    public func getInitialChatHistory() {
        var userInfo: [AnyHashable: Any] = [:]
        userInfo["room"] = room.token

        // Clear expired messages
        removeExpiredMessages()

        var lastReadMessageId = 0
        // If the chat supports read markers and this is not a thread controller, start from the room's last read message.
        // In thread controllers, always start from the latest message (lastReadMessageId = 0) because the room's last read message
        // might be outdated and older than the thread's first message, which would lead to a 304 response.
        if NCDatabaseManager.sharedInstance().roomHasTalkCapability(.chatReadMarker, for: room), !isThreadController {
            lastReadMessageId = room.lastReadMessage
        }

        fetchHistoryUntilVisible(fromMessageId: lastReadMessageId, forInitialChatHistory: true, isFirstIteration: true) { messages, lastCommonReadMessage, error, statusCode in
            if let error {
                if self.isChatBeingBlocked(statusCode) {
                    self.notifyChatIsBlocked()
                    return
                }
                userInfo["error"] = error
                NSLog("Could not get initial chat history. Error: \(error.description)")
            } else if let messages, !messages.isEmpty {
                userInfo["messages"] = messages
                self.updateLastMessageIfNeeded(fromMessages: messages)
            }

            NotificationCenter.default.post(name: .NCChatControllerDidReceiveInitialChatHistory, object: self, userInfo: userInfo)

            self.checkLastCommonReadMessage(lastCommonReadMessage)
        }
    }

    public func getHistoryBatch(fromMessagesId messageId: Int) {
        var userInfo: [AnyHashable: Any] = [:]
        userInfo["room"] = room.token

        fetchHistoryUntilVisible(fromMessageId: messageId, forInitialChatHistory: false, isFirstIteration: true) { messages, _, error, statusCode in
            if statusCode == 304 {
                self.updateHistoryFlagInFirstBlock()
            }
            if let error {
                if self.isChatBeingBlocked(statusCode) {
                    self.notifyChatIsBlocked()
                    return
                }
                userInfo["error"] = error
                if statusCode != 304 {
                    NSLog("Could not get chat history. Error: \(error.description)")
                }
            } else if let messages, !messages.isEmpty {
                userInfo["messages"] = messages
            }

            NotificationCenter.default.post(name: .NCChatControllerDidReceiveChatHistory, object: self, userInfo: userInfo)
        }
    }

    private func fetchHistoryUntilVisible(fromMessageId messageId: Int, forInitialChatHistory: Bool, isFirstIteration: Bool, completion: @escaping (_ messages: [NCChatMessage]?, _ lastCommonReadMessage: Int, _ error: OcsError?, _ statusCode: Int) -> Void) {
        var messageId = messageId
        let lastChatBlock = chatBlocksForRoomOrThread().last

        // First, try to load messages from local storage (DB)
        if let lastChatBlock {
            let canUseLocalStorage: Bool

            if forInitialChatHistory {
                // For initial chat history: make sure messageId is inside the last chat block
                canUseLocalStorage = lastChatBlock.newestMessageId > 0 &&
                                     messageId >= lastChatBlock.oldestMessageId &&
                                     lastChatBlock.newestMessageId >= messageId
            } else {
                // For history batch: just make sure messageId is newer than last chat block's oldest message
                canUseLocalStorage = lastChatBlock.newestMessageId > 0 &&
                                     messageId >= lastChatBlock.oldestMessageId
            }

            if canUseLocalStorage {
                // For initial chat history: always get batch from last chat block's newest message, even if it's not the first iteration.
                // For history batch: get batch from the passed messageId. If it's not the first iteration, we will just skip invisible messages
                // from previous iterations and not pass them to the chat view.
                let storedMessages = getBatchOfMessages(inBlock: lastChatBlock,
                                                        fromMessageId: forInitialChatHistory ? lastChatBlock.newestMessageId : messageId,
                                                        included: forInitialChatHistory,
                                                        ensureIncludesMessageId: forInitialChatHistory ? messageId : 0)

                for message in storedMessages {
                    // Since the passed messageId might not be the lowest one, we update it here to ensure we request the missing messages
                    if message.messageId < messageId {
                        messageId = message.messageId
                    }

                    // If there is at least one visible message, we can stop fetching messages and pass them
                    if willBeVisibleMessage(message) {
                        completion(storedMessages, 0, nil, 0)
                        return
                    }
                }
            }
        }

        // If no messages are found or visible in last chat block, fall back to fetching them from the server
        getHistoryTask = NCAPIController.sharedInstance().receiveChatMessages(ofRoom: room.token, fromLastMessageId: messageId, inThread: threadId, history: true, includeLastMessage: forInitialChatHistory, timeout: false, limit: NCAPIController.shared.kReceivedChatMessagesLimit, lastCommonReadMessage: room.lastCommonReadMessage, setReadMarker: true, markNotificationsAsRead: true, forAccount: account) { messages, lastKnownMessage, lastCommonReadMessage, error, statusCode in
            if self.stopChatMessagesPoll {
                return
            }

            // Error handling
            if let error {
                completion(nil, 0, error, statusCode)
                return
            }

            // Update chat blocks
            // Only store a new block when getting initial history and we are in the first iteration.
            // Otherwise, only update the chat blocks with history messages ("backwards").
            if forInitialChatHistory, isFirstIteration {
                self.updateChatBlocks(withReceivedMessages: messages, newestKnown: messageId, andLastKnown: lastKnownMessage)
            } else {
                self.updateChatBlocks(withLastKnown: lastKnownMessage)
            }

            // Store new messages
            if let messages, !messages.isEmpty {
                self.storeMessages(messages)

                let lastChatBlock = self.chatBlocksForRoomOrThread().last
                // For initial chat history: always get batch from last chat block's newest message, even if it's not the first iteration.
                // For history batch: get batch from the passed messageId. If it's not the first iteration, we will just skip invisible messages
                // from previous iterations and not pass them to the chat view.
                let history = self.getBatchOfMessages(inBlock: lastChatBlock,
                                                      fromMessageId: forInitialChatHistory ? (lastChatBlock?.newestMessageId ?? 0) : messageId,
                                                      included: forInitialChatHistory,
                                                      ensureIncludesMessageId: forInitialChatHistory ? messageId : 0)

                for message in history where self.willBeVisibleMessage(message) {
                    completion(history, lastCommonReadMessage, nil, 0)
                    return
                }

                // Prevent infinite loop in case there are no new messages
                if statusCode != 304 {
                    // Recursively fetch messages until finding visible ones
                    self.fetchHistoryUntilVisible(fromMessageId: lastKnownMessage,
                                                  forInitialChatHistory: forInitialChatHistory,
                                                  isFirstIteration: false,
                                                  completion: completion)
                    return
                }
            }

            completion([], 0, nil, 0)
        }
    }

    public func getHistoryBatchOffline(fromMessagesId messageId: Int) {
        var userInfo: [AnyHashable: Any] = [:]
        userInfo["room"] = room.token

        let chatBlocks = chatBlocksForRoomOrThread()
        var historyBatch: [NCChatMessage] = []
        if !chatBlocks.isEmpty {
            var index = chatBlocks.count - 1
            while index >= 0 {
                let currentBlock = chatBlocks[index]
                var noMoreMessagesToRetrieveInBlock = false
                if currentBlock.oldestMessageId < messageId {
                    let storedMessages = getBatchOfMessages(inBlock: currentBlock, fromMessageId: messageId, included: false, ensureIncludesMessageId: 0)
                    historyBatch = storedMessages
                    if !storedMessages.isEmpty {
                        break
                    } else {
                        // We use this flag in case the rest of the messages in current block
                        // are system messages invisible for the user.
                        noMoreMessagesToRetrieveInBlock = true
                    }
                }
                if index > 0, currentBlock.oldestMessageId == messageId || noMoreMessagesToRetrieveInBlock {
                    let previousBlock = chatBlocks[index - 1]
                    let storedMessages = getBatchOfMessages(inBlock: previousBlock, fromMessageId: previousBlock.newestMessageId, included: true, ensureIncludesMessageId: 0)
                    historyBatch = storedMessages
                    userInfo["shouldAddBlockSeparator"] = true
                    break
                }
                index -= 1
            }
        }

        if historyBatch.isEmpty {
            userInfo["noMoreStoredHistory"] = true
        }

        userInfo["messages"] = historyBatch
        NotificationCenter.default.post(name: .NCChatControllerDidReceiveChatHistory, object: self, userInfo: userInfo)
    }

    private func stopReceivingChatHistory() {
        getHistoryTask?.cancel()
    }

    private func startReceivingChatMessages(fromMessagesId messageId: Int, withTimeout timeout: Bool) {
        stopChatMessagesPoll = false
        pullMessagesTask?.cancel()
        pullMessagesTask = NCAPIController.sharedInstance().receiveChatMessages(ofRoom: room.token, fromLastMessageId: messageId, inThread: threadId, history: false, includeLastMessage: false, timeout: timeout, limit: NCAPIController.shared.kReceivedChatMessagesLimit, lastCommonReadMessage: room.lastCommonReadMessage, setReadMarker: true, markNotificationsAsRead: true, forAccount: account) { messages, lastKnownMessage, lastCommonReadMessage, error, statusCode in
            if self.stopChatMessagesPoll {
                return
            }

            if let error {
                if self.isChatBeingBlocked(statusCode) {
                    self.notifyChatIsBlocked()
                    return
                }

                if statusCode == 404 {
                    NCLog.log("Thread not found error: \(error.description)")
                    NotificationCenter.default.post(name: .NCChatControllerDidReceiveThreadNotFound, object: self, userInfo: nil)
                    return
                }

                if statusCode == 429 {
                    NCLog.log("Brute-force protected, received 429 while receiving messages. No further polling.")
                    return
                }

                if statusCode != 304 {
                    NCLog.log("Could not get new chat messages. Error: \(error.description)")
                }
            } else {
                // Update last chat block
                self.updateLastChatBlock(withNewestKnown: lastKnownMessage)

                // Store new messages
                if let messages, !messages.isEmpty {
                    self.storeMessages(messages)
                    self.checkForNewMessages(fromMessageId: messageId)

                    for messageDict in messages {
                        let message = NCChatMessage(dictionary: messageDict as [AnyHashable: Any], andAccountId: self.account.accountId)

                        // When we receive a "history_cleared" message, we don't continue here, as otherwise
                        // we would request new messages, but instead, we need to request the initial history again
                        if message?.systemMessage == "history_cleared" {
                            return
                        }
                    }
                }
            }

            self.hasReceivedMessagesFromServer = true

            self.checkLastCommonReadMessage(lastCommonReadMessage)

            if error?.underlyingError.code != NSURLErrorCancelled {
                let chatIsUpToDate = statusCode == 304
                let lastChatBlock = self.chatBlocksForRoomOrThread().last

                if chatIsUpToDate, let extSignaling = self.externalSignalingController, extSignaling.hasChatRelay {
                    print("Chat is up to date, now processing new messages from the chat relay")
                    self.startProcessingChatRelayMessages()
                    return
                }

                self.startReceivingChatMessages(fromMessagesId: lastChatBlock?.newestMessageId ?? 0, withTimeout: chatIsUpToDate)
            }
        }
    }

    public func startReceivingNewChatMessages() {
        let lastChatBlock = chatBlocksForRoomOrThread().last
        startReceivingChatMessages(fromMessagesId: lastChatBlock?.newestMessageId ?? 0, withTimeout: false)
    }

    public func stopReceivingNewChatMessages() {
        // Reset on the relay queue to keep all chatRelayState access on a single queue.
        chatRelayMessagesQueue?.async {
            self.chatRelayState = .inactive
        }
        stopChatMessagesPoll = true
        pullMessagesTask?.cancel()
    }

    public func sendChatMessage(_ message: String, replyTo: Int, referenceId: String?, silently: Bool) {
        let bgTask = BGTaskHelper.startBackgroundTask(withName: "NCChatControllerSendMessage") { _ in
            NCLog.log("ExpirationHandler called - sendChatMessage")
        }

        var userInfo: [AnyHashable: Any] = [:]
        userInfo["message"] = message

        var retryCount = 0

        if let referenceId {
            // Reset offline message flag before retrying to send to prevent race conditions and
            // possible ending up with multiple identical messages sent
            transactionForMessage(withReferenceId: referenceId) { message in
                message?.isOfflineMessage = false
                retryCount = message?.offlineMessageRetryCount ?? 0
            }
        }

        NCAPIController.sharedInstance().sendChatMessage(message, toRoom: room.token, threadTitle: nil, replyTo: replyTo, referenceId: referenceId, silently: silently, forAccount: account) { error in
            if let referenceId {
                userInfo["referenceId"] = referenceId
            }

            if let error {
                userInfo["error"] = error

                if let referenceId {
                    if retryCount >= 5 {
                        // After 5 retries, we assume sending is not possible
                        self.transactionForMessage(withReferenceId: referenceId) { message in
                            message?.sendingFailed = true
                            message?.isOfflineMessage = false
                        }
                    } else {
                        self.transactionForMessage(withReferenceId: referenceId) { message in
                            message?.sendingFailed = false
                            message?.isOfflineMessage = true
                            retryCount += 1
                            message?.offlineMessageRetryCount = retryCount
                        }

                        userInfo["isOfflineMessage"] = true
                    }
                }

                NCLog.log("Could not send chat message. Error: \(error.description)")
            } else {
                NCIntentController.sharedInstance().donateSendMessageIntent(for: self.room)
            }

            NotificationCenter.default.post(name: .NCChatControllerDidSendChatMessage, object: self, userInfo: userInfo)

            bgTask.stopBackgroundTask()
        }
    }

    public func send(_ message: NCChatMessage) {
        guard message.messageType == kMessageTypeVoiceMessage else {
            sendChatMessage(message.sendingMessage, replyTo: message.parentMessageId, referenceId: message.referenceId, silently: message.isSilent)
            return
        }

        var talkMetaData: [String: Any] = ["messageType": "voice-message"]

        if message.parentMessageId > 0 {
            talkMetaData["replyTo"] = message.parentMessageId
        }

        if isThreadController {
            talkMetaData["threadId"] = threadId
        }

        let uploadCompletion: (Int, NSString?) -> Void = { statusCode, _ in
            switch statusCode {
            case 200:
                NSLog("Successfully uploaded and shared voice message.")
            case 403:
                NSLog("Failed to share voice message.")
            case 404, 409:
                NSLog("Failed to check or create attachment folder.")
            case 507:
                NSLog("User storage quota exceeded.")
            default:
                NSLog("Failed to upload voice message with error code: %ld", statusCode)
            }
        }

        if room.supportsConversationSubfolders {
            let fileName = message.message ?? ""

            NCAPIController.sharedInstance().probeConversationAttachmentFolder(inRoom: room.token, withFileNames: [fileName], forAccount: account) { draftFolder, _, error in
                guard error == nil, let draftFolder else {
                    NSLog("Could not probe conversation attachment folder for voice message.")
                    return
                }

                let fileExtension = URL(string: fileName)?.pathExtension ?? ""
                let extensionSuffix = !fileExtension.isEmpty ? ".\(fileExtension)" : ""
                let tempName = UUID().uuidString + extensionSuffix
                let draftPath = "\(draftFolder)/\(tempName)"
                let serverPath = "/\(draftPath)"
                let fileServerURL = "\(self.account.server)/remote.php/dav/files/\(self.account.userId)\(serverPath)"

                ChatFileUploader.uploadFile(localPath: message.file()?.fileStatus?.fileLocalPath ?? "",
                                            fileServerURL: fileServerURL,
                                            fileServerPath: serverPath,
                                            draftPath: draftPath,
                                            talkMetaData: talkMetaData,
                                            temporaryMessage: message,
                                            room: self.room,
                                            completion: uploadCompletion)
            }
        } else {
            NCAPIController.sharedInstance().uniqueNameForFileUpload(withName: message.message ?? "", isOriginalName: true, forAccount: account) { fileServerURL, fileServerPath, _, _ in
                if let fileServerURL, let fileServerPath {
                    ChatFileUploader.uploadFile(localPath: message.file()?.fileStatus?.fileLocalPath ?? "",
                                                fileServerURL: fileServerURL,
                                                fileServerPath: fileServerPath,
                                                draftPath: nil,
                                                talkMetaData: talkMetaData,
                                                temporaryMessage: message,
                                                room: self.room,
                                                completion: uploadCompletion)
                } else {
                    NSLog("Could not find unique name for voice message file.")
                }
            }
        }
    }

    private func checkLastCommonReadMessage(_ lastCommonReadMessage: Int) {
        guard lastCommonReadMessage > 0 else { return }

        let newerCommonReadReceived = lastCommonReadMessage > self.room.lastCommonReadMessage

        if newerCommonReadReceived {
            self.room.lastCommonReadMessage = lastCommonReadMessage
            NCRoomsManager.shared.updateLastCommonReadMessage(lastCommonReadMessage, forRoom: self.room)

            var userInfo: [AnyHashable: Any] = [:]
            userInfo["room"] = self.room.token
            userInfo["lastCommonReadMessage"] = lastCommonReadMessage
            NotificationCenter.default.post(name: .NCChatControllerDidReceiveNewerCommonReadMessage, object: self, userInfo: userInfo)
        }
    }

    private func isChatBeingBlocked(_ statusCode: Int) -> Bool {
        return statusCode == 412
    }

    private func notifyChatIsBlocked() {
        var userInfo: [AnyHashable: Any] = [:]
        userInfo["room"] = room.token
        NotificationCenter.default.post(name: .NCChatControllerDidReceiveChatBlocked, object: self, userInfo: userInfo)
    }

    public func stop() {
        stopReceivingNewChatMessages()
        stopReceivingChatHistory()
        hasReceivedMessagesFromServer = false
    }

    public func clearHistoryAndResetChatController() {
        pullMessagesTask?.cancel()
        removeAllStoredMessagesAndChatBlocks()
        room.lastReadMessage = 0
    }

    public func hasHistory(fromMessageId messageId: Int) -> Bool {
        let firstChatBlock = chatBlocksForRoomOrThread().first
        if let firstChatBlock, firstChatBlock.oldestMessageId == messageId {
            return firstChatBlock.hasHistory
        }
        return true
    }

    public func getMessageContext(forMessageId messageId: Int, withLimit limit: Int, completionBlock block: ((_ messages: [NCChatMessage]?) -> Void)?) {
        NCAPIController.sharedInstance().getMessageContext(inRoom: room.token, forMessageId: messageId, inThread: threadId, withLimit: limit, forAccount: account) { messages, error in
            if error != nil {
                block?(nil)
                return
            }

            if let messages {
                for message in messages {
                    guard let messageFile = message.file() else {
                        continue
                    }

                    // Try to get the stored preview height from our database, when the message is already stored
                    if let managedMessage = NCChatMessage.objects(where: "internalId = %@", message.internalId ?? "").firstObject() as? NCChatMessage,
                       let managedFile = managedMessage.file(), managedFile.previewImageHeight > 0 {
                        messageFile.previewImageHeight = managedFile.previewImageHeight
                    }
                }
            }

            block?(messages)
        }
    }

    public func getSingleMessage(withMessageId messageId: Int, completionBlock block: ((_ message: NCChatMessage?) -> Void)?) {
        let query = NSPredicate(format: "accountId = %@ AND token = %@ AND messageId == %ld", account.accountId, room.token, messageId)
        if let message = NCChatMessage.objects(with: query).firstObject() as? NCChatMessage {
            block?(message)
            return
        }

        NCAPIController.sharedInstance().receiveChatMessages(ofRoom: room.token, fromLastMessageId: messageId, inThread: 0, history: true, includeLastMessage: true, timeout: false, limit: 1, lastCommonReadMessage: 0, setReadMarker: false, markNotificationsAsRead: false, forAccount: account) { messages, _, _, error, _ in
            if let error {
                NSLog("Could not get single message from server. Error: \(error.description)")
                block?(nil)
            } else {
                let message = NCChatMessage(dictionary: messages?.first, andAccountId: self.account.accountId)

                // The API will return the previous available message in case the messageId is not found.
                // Therefore we need to make sure, that we received the message we are looking for.
                if let message, message.messageId == messageId {
                    block?(message)
                    return
                }

                block?(nil)
            }
        }
    }
}
