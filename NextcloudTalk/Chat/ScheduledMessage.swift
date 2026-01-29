//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

public class ScheduledMessage {

    public var id: String
    public var actor: TalkActor?
    public var threadId: Int = 0
    public var message: String
    public var messageType: String
    public var parentMessage: NCChatMessage?
    public var silent: Bool
    public var createdAtTimestamp: Int
    public var sendAtTimestamp: Int

    private var account: TalkAccount

    init?(dictionary dict: [String: Any]?, withAccount account: TalkAccount) {
        guard let dict else { return nil }

        self.account = account

        self.id = dict["id"] as? String ?? ""
        self.threadId = dict["threadId"] as? Int ?? 0
        self.message = dict["message"] as? String ?? ""
        self.messageType = dict["messageType"] as? String ?? ""
        self.silent = dict["silent"] as? Bool ?? false
        self.createdAtTimestamp = dict["createdAt"] as? Int ?? 0
        self.sendAtTimestamp = dict["sendAt"] as? Int ?? 0

        if let actorId = dict["actorId"] as? String, let actorType = dict["actorType"] as? String {
            self.actor = TalkActor(actorId: actorId, actorType: actorType)
        }

        if let parentMessage = dict["parent"] as? [String: Any] {
            self.parentMessage = NCChatMessage(dictionary: parentMessage, andAccountId: account.accountId)
        }
    }

    public func asChatMessage() -> NCChatMessage {
        let message = NCChatMessage()

        message.messageId = Int(self.id) ?? 0
        message.actorId = self.account.userId
        message.actorType = "users"
        message.actorDisplayName = account.userDisplayName
        message.accountId = self.account.accountId

        message.timestamp = self.sendAtTimestamp
        message.message = self.message
        message.isSilent = self.silent
        message.isMarkdownMessage = true

        if let parentMessage {
            message.parentId = parentMessage.internalId
        }

        message.threadId = self.threadId

        return message
    }
}
