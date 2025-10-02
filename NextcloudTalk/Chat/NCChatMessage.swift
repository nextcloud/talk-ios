//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SwiftyAttributes

@objc extension NCChatMessage {

    public var isSystemMessage: Bool {
        return self.systemMessage != nil && !self.systemMessage.isEmpty
    }

    public var isEmojiMessage: Bool {
        return self.message != nil && self.message.containsOnlyEmoji && self.message.emojiCount <= 3
    }

    public var isUpdateMessage: Bool {
        return self.systemMessage == "message_deleted" ||
               self.systemMessage == "reaction" ||
               self.systemMessage == "reaction_revoked" ||
               self.systemMessage == "reaction_deleted" ||
               self.systemMessage == "poll_voted" ||
               self.systemMessage == "message_edited" ||
               self.systemMessage == "thread_created" ||
               self.systemMessage == "thread_renamed"
    }

    public var isThreadCreatedMessage: Bool {
        return self.systemMessage == "thread_created"
    }

    public var isDeletedMessage: Bool {
        return self.messageType == kMessageTypeCommentDeleted
    }

    public var isVoiceMessage: Bool {
        return self.messageType == kMessageTypeVoiceMessage
    }

    public var isCommandMessage: Bool {
        return self.messageType == kMessageTypeCommand
    }

    public func isMessage(from userId: String) -> Bool {
        return self.actorType == "users" && self.actorId == userId
    }

    public func isDeletable(for account: TalkAccount, in room: NCRoom) -> Bool {
        guard !self.isDeleting else { return false }

        let sixHoursAgoTimestamp = Int(Date().timeIntervalSince1970 - (6 * 3600))

        // Check server capability for normal messages
        var commentDeletion = NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityDeleteMessages, forAccountId: account.accountId)
        commentDeletion = commentDeletion && self.messageType == kMessageTypeComment
        commentDeletion = commentDeletion && self.file() == nil
        commentDeletion = commentDeletion && !self.isObjectShare

        // Check server capability for files or shared objects
        var objectDeletion = NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityRichObjectDelete)
        objectDeletion = objectDeletion && (self.file() != nil || self.isVoiceMessage || self.isObjectShare)

        // Check if user is allowed to delete a message
        let sameUser = self.isMessage(from: account.userId)
        let moderatorUser = (room.type != .oneToOne && room.type != .formerOneToOne) && (room.participantType == .owner || room.participantType == .moderator)

        let serverCanDeleteMessage = commentDeletion || objectDeletion
        let userCanDeleteMessage = sameUser || moderatorUser

        let noTimeLimitForMessageDeletion = NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityDeleteMessagesUnlimited, forAccountId: account.accountId)
        let deletionAllowedByTime = noTimeLimitForMessageDeletion || (self.timestamp >= sixHoursAgoTimestamp)

        return serverCanDeleteMessage && userCanDeleteMessage && deletionAllowedByTime
    }

    public func isEditable(for account: TalkAccount, in room: NCRoom) -> Bool {
        guard !self.isDeleting else { return false }

        let twentyFourHoursAgoTimestamp = Int(Date().timeIntervalSince1970 - (24 * 3600))

        var serverCanEditMessage = NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityEditMessages, forAccountId: account.accountId)
        serverCanEditMessage = serverCanEditMessage && self.messageType == kMessageTypeComment && !self.isObjectShare

        let sameUser = self.isMessage(from: account.userId)
        let moderatorUser = (room.type != .oneToOne && room.type != .formerOneToOne) && (room.participantType == .owner || room.participantType == .moderator)
        let botInOneToOne = room.type == .oneToOne && self.actorType == AttendeeType.bots.rawValue && self.actorId.starts(with: NCAttendeeBotPrefix)

        let userCanEditMessage = sameUser || moderatorUser || botInOneToOne

        let noTimeLimitForMessageEdit = (room.type == .noteToSelf) && NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityEditMessagesNoteToSelf, forAccountId: account.accountId)
        let editAllowedByTime = noTimeLimitForMessageEdit || (self.timestamp >= twentyFourHoursAgoTimestamp)

        return serverCanEditMessage && userCanEditMessage && editAllowedByTime
    }

    public var isObjectShare: Bool {
        return self.message != nil && self.message == "{object}" && self.messageParameters["object"] != nil
    }

    public var richObjectFromObjectShare: [AnyHashable: Any] {
        guard self.isObjectShare,
              let objectDict = self.messageParameters["object"] as? [AnyHashable: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: objectDict),
              let jsonString = String(data: jsonData, encoding: .utf8),
              let parameter = NCMessageParameter(dictionary: objectDict)
        else { return [:] }

        return [
            "objectType": parameter.type!,
            "objectId": parameter.parameterId!,
            "metaData": jsonString
        ]
    }

    public var poll: NCMessageParameter? {
        guard let objectParameter, objectParameter.type == "talk-poll"
        else { return nil }

        return objectParameter
    }

    public var objectParameter: NCMessageParameter? {
        guard self.isObjectShare,
              let objectDict = self.messageParameters["object"] as? [AnyHashable: Any],
              let objectParameter = NCMessageParameter(dictionary: objectDict)
        else { return nil }

        return objectParameter
    }

    public var messageParameters: [AnyHashable: Any] {
        guard let data = self.messageParametersJSONString?.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [AnyHashable: Any]
        else { return [:] }

        return dict
    }

    public var mentionMessageParameters: [String: NCMessageParameter] {
        var result: [String: NCMessageParameter] = [:]

        for case let (key as String, value as [String: String]) in self.messageParameters {
            guard key.hasPrefix("mention-"), let parameter = NCMessageParameter(dictionary: value), parameter.isMention() else { continue }

            if parameter.mention == nil, let parameterId = parameter.parameterId, let paramaterDisplayName = parameter.name {
                // Try to reconstruct the mention for unsupported servers
                parameter.mention = Mention(id: parameterId, label: paramaterDisplayName)
            }

            if parameter.mention != nil {
                result[key] = parameter
            }
        }

        return result
    }

    // TODO: Should probably be an optional?
    public var systemMessageFormat: NSMutableAttributedString {
        guard let message = self.parsedMessage() else { return NSMutableAttributedString(string: "") }

        let paragraphStyle: NSMutableParagraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = NSTextAlignment.center

        return message.withTextColor(.tertiaryLabel).withParagraphStyle(paragraphStyle)
    }

    // TODO: Should probably be an optional?
    /// 'Hello {mention-user1}' -> 'Hello @user1'
    public var sendingMessage: String {
        guard var resultMessage = self.message else { return "" }

        resultMessage = resultMessage.trimmingCharacters(in: .whitespacesAndNewlines)

        for case let (key as String, value as [AnyHashable: Any]) in self.messageParameters {
            if let parameter = NCMessageParameter(dictionary: value), let mention = parameter.mention {
                resultMessage = resultMessage.replacingOccurrences(of: "{\(key)}", with: mention.idForChat)
            }
        }

        return resultMessage
    }

    /// 'Hello {mention-user1}' -> 'Hello @User1 Displayname'
    public var sendingMessageWithDisplayNames: String? {
        guard var resultMessage = self.message else { return nil }

        resultMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)

        // TODO: Could use mentionMessageParameters directly here?
        for case let (key as String, value as [AnyHashable: Any]) in self.messageParameters {
            if let parameter = NCMessageParameter(dictionary: value), let mention = parameter.mention {
                resultMessage = resultMessage.replacingOccurrences(of: "{\(key)}", with: mention.labelForChat)
            }
        }

        return resultMessage
    }

    public var parent: NCChatMessage? {
        guard !self.isDeletedMessage, self.parentId != nil else { return nil }

        var unmanagedChatMessage: NCChatMessage?

        if let managedChatMessage = NCChatMessage.objects(where: "internalId = %@", self.parentId).firstObject() {
            unmanagedChatMessage = NCChatMessage(value: managedChatMessage)
        }

        return unmanagedChatMessage
    }

    public var parentMessageId: Int {
        return self.parent?.messageId ?? -1
    }

    public func willShowParentMessageInThread(_ thread: NCThread?) -> Bool {
        if parent == nil {
            return false
        }

        if let parent = parent,
           let thread = thread,
           parent.internalId == thread.firstMessageId {
            return false
        }

        return true
    }

    public func isReactionBeingModified(_ reaction: String) -> Bool {
        if let reaction = temporaryReactions().compactMap({ $0 as? NCChatReaction }).first(where: { $0.reaction == reaction }) {
            return reaction.state == .adding || reaction.state == .removing
        }

        return false
    }

    public func removeReactionFromTemporaryReactions(_ reaction: String) {
        if let removeReaction = self.temporaryReactions().first(where: { ($0 as? NCChatReaction)?.reaction == reaction }) {
            self.temporaryReactions().remove(removeReaction)
        }
    }

    public func setOrUpdateTemporaryReaction(_ reaction: String, state: NCChatReactionState) {
        if let updateReaction = temporaryReactions().compactMap({ $0 as? NCChatReaction }).first(where: { $0.reaction == reaction }) {
            updateReaction.reaction = reaction
            updateReaction.state = state
        } else {
            let temporaryReaction = NCChatReaction()
            temporaryReaction.reaction = reaction
            temporaryReaction.state = state
            self.temporaryReactions().add(temporaryReaction)
        }
    }

    internal var isReferenceApiSupported: Bool {
        // Check capabilities directly, otherwise NCSettingsController introduces new dependencies in NotificationServiceExtension
        if let accountId, let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: accountId) {
            return serverCapabilities.referenceApiSupported
        }

        return false
    }

    public func isSameMessage(_ message: NCChatMessage) -> Bool {
        if self.isTemporary {
            return self.referenceId == message.referenceId
        }

        return self.messageId == message.messageId
    }

    public var collapsedMessageParameters: [AnyHashable: Any] {
        guard let data = self.collapsedMessageParametersJSONString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [AnyHashable: Any]
        else { return [:] }

        return dict
    }

    public func setCollapsedMessageParameters(_ messageParameters: [AnyHashable: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: messageParameters),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else { return }

        self.collapsedMessageParametersJSONString = jsonString
    }

    public var actor: TalkActor {
        return TalkActor(actorId: self.actorId, actorType: self.actorType, actorDisplayName: self.actorDisplayName)
    }

    public var account: TalkAccount? {
        guard let accountId else { return nil }
        return NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId)
    }

    public var messageIconName: String? {
        if let file = self.file() {
            if let mimetype = file.mimetype {
                if NCUtils.isImage(fileType: mimetype) {
                    return "photo"
                } else if NCUtils.isVideo(fileType: mimetype) {
                    return "movieclapper"
                } else if NCUtils.isVCard(fileType: mimetype) {
                    return "person.text.rectangle"
                } else if NCUtils.isAudio(fileType: mimetype) {
                    return "music.note"
                }
            }

            if self.isVoiceMessage {
                return "mic"
            }

            return "doc"
        } else if poll != nil {
            return "chart.bar"
        } else if deckCard() != nil {
            return "rectangle.stack"
        } else if geoLocation() != nil {
            return "location"
        }

        return nil
    }

    public var isAnimatableGif: Bool {
        guard let accountId, let file = self.file(), let mimetype = file.mimetype else { return false }

        let capabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: accountId)

        guard NCUtils.isGif(fileType: mimetype), let maxGifSize = capabilities?.maxGifSize, maxGifSize > 0 else { return false }

        return file.size <= maxGifSize
    }

    public func messagePreview(forOneToOneRoom: Bool = false) -> NSMutableAttributedString? {
        guard let account = self.account
        else { return nil }

        let ownMessage = self.actorId == account.userId
        var actorName = self.actorDisplayName.components(separatedBy: " ").first ?? ""

        // For own messages
        if ownMessage {
            actorName = NSLocalizedString("You", comment: "")
        }

        // For guests
        if self.actorDisplayName.isEmpty {
            actorName = NSLocalizedString("Guest", comment: "")
        }

        // No actor name cases
        if self.isSystemMessage || (forOneToOneRoom && !ownMessage) {
            actorName = ""
        }

        // Add separator
        if !actorName.isEmpty {
            actorName = "\(actorName): "
        }

        let lastMessageString = NSMutableAttributedString(string: actorName)

        if let messageIconName = self.messageIconName, let messageIcon = UIImage(systemName: messageIconName) {
            let attachmentString = NSMutableAttributedString(attachment: NSTextAttachment(image: messageIcon))
            attachmentString.append(NSAttributedString(string: " "))

            lastMessageString.append(attachmentString)
        }

        let parsedMarkdownString = String(self.parsedMarkdown().string.prefix(80))
        lastMessageString.append(NSAttributedString(string: parsedMarkdownString))

        return lastMessageString.withFont(.preferredFont(forTextStyle: .callout)).withTextColor(.secondaryLabel)
    }
}
