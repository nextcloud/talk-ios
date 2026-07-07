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
        // Hide system messages for automatic unpin
        if self.systemMessage == "message_unpinned", self.actorType == "guests", self.actorId == "system" {
            return true
        }

        return self.systemMessage == "message_deleted" ||
               self.systemMessage == "reaction" ||
               self.systemMessage == "reaction_revoked" ||
               self.systemMessage == "reaction_deleted" ||
               self.systemMessage == "poll_voted" ||
               self.systemMessage == "message_edited" ||
               self.systemMessage == "thread_created" ||
               self.systemMessage == "thread_renamed"
    }

    public var isVisibleUpdateMessage: Bool {
        return self.systemMessage == "message_pinned" ||
               self.systemMessage == "message_unpinned"
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

    // Whether the message's "user" parameter (e.g. the target of a moderator promotion/demotion)
    // refers to the given user.
    public func userParameterRefersTo(_ userId: String) -> Bool {
        guard let userParameter = NCMessageParameter(dictionary: self.messageParameters["user"] as? [String: Any]) else {
            return false
        }
        return userParameter.type == "user" && userParameter.parameterId == userId
    }

    // Whether the message was sent by the command line (e.g. an administrator action).
    public var isFromCommandLine: Bool {
        return self.actorId == "cli" && self.actorType == "guests"
    }

    public func isDeletable(for account: TalkAccount, in room: NCRoom) -> Bool {
        guard !self.isDeleting else { return false }

        let sixHoursAgoTimestamp = Int(Date().timeIntervalSince1970 - (6 * 3600))

        // Check server capability for normal messages
        var commentDeletion = NCDatabaseManager.sharedInstance().serverHasTalkCapability(.deleteMessages, forAccountId: account.accountId)
        commentDeletion = commentDeletion && self.messageType == kMessageTypeComment
        commentDeletion = commentDeletion && self.file() == nil
        commentDeletion = commentDeletion && !self.isObjectShare

        // Check server capability for files or shared objects
        var objectDeletion = NCDatabaseManager.sharedInstance().serverHasTalkCapability(.richObjectDelete)
        objectDeletion = objectDeletion && (self.file() != nil || self.isVoiceMessage || self.isObjectShare)

        // Check if user is allowed to delete a message
        let sameUser = self.isMessage(from: account.userId)
        let moderatorUser = !room.isOneToOne && (room.participantType == .owner || room.participantType == .moderator)

        let serverCanDeleteMessage = commentDeletion || objectDeletion
        let userCanDeleteMessage = sameUser || moderatorUser

        let noTimeLimitForMessageDeletion = NCDatabaseManager.sharedInstance().serverHasTalkCapability(.deleteMessagesUnlimited, forAccountId: account.accountId)
        let deletionAllowedByTime = noTimeLimitForMessageDeletion || (self.timestamp >= sixHoursAgoTimestamp)

        return serverCanDeleteMessage && userCanDeleteMessage && deletionAllowedByTime
    }

    public func isEditable(for account: TalkAccount, in room: NCRoom) -> Bool {
        guard !self.isDeleting else { return false }

        let twentyFourHoursAgoTimestamp = Int(Date().timeIntervalSince1970 - (24 * 3600))

        var serverCanEditMessage = NCDatabaseManager.sharedInstance().serverHasTalkCapability(.editMessages, forAccountId: account.accountId)
        serverCanEditMessage = serverCanEditMessage && self.messageType == kMessageTypeComment && !self.isObjectShare

        let sameUser = self.isMessage(from: account.userId)
        let moderatorUser = !room.isOneToOne && (room.participantType == .owner || room.participantType == .moderator)
        let botInOneToOne = room.type == .oneToOne && self.actorType == AttendeeType.bots.rawValue && self.actorId.starts(with: NCAttendeeBotPrefix)

        let userCanEditMessage = sameUser || moderatorUser || botInOneToOne

        let noTimeLimitForMessageEdit = (room.type == .noteToSelf) && NCDatabaseManager.sharedInstance().serverHasTalkCapability(.editMessagesNoteToSelf, forAccountId: account.accountId)
        let editAllowedByTime = noTimeLimitForMessageEdit || (self.timestamp >= twentyFourHoursAgoTimestamp)

        return serverCanEditMessage && userCanEditMessage && editAllowedByTime
    }

    public var isObjectShare: Bool {
        return self.message != nil && self.message == "{object}" && self.messageParameters["object"] != nil
    }

    public var isPinned: Bool {
        return self.pinnedActorId != nil
    }

    public var richObjectFromObjectShare: [String: Any] {
        guard self.isObjectShare,
              let objectDict = self.messageParameters["object"] as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: objectDict),
              let jsonString = String(data: jsonData, encoding: .utf8),
              let parameter = NCMessageParameter(dictionary: objectDict)
        else { return [:] }

        return [
            "objectType": parameter.type,
            "objectId": parameter.parameterId,
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
              let objectDict = self.messageParameters["object"] as? [String: Any],
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
            guard key.hasPrefix("mention-"), let parameter = NCMessageParameter(dictionary: value), parameter.isMention else { continue }

            if parameter.mention == nil {
                // Try to reconstruct the mention for unsupported servers
                parameter.mention = Mention(id: parameter.parameterId, label: parameter.name)
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

        for case let (key as String, value as [String: Any]) in self.messageParameters {
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
        for case let (key as String, value as [String: Any]) in self.messageParameters {
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

        if let parent, let thread, parent.internalId == thread.firstMessageId {
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
            let temporaryReaction = NCChatReaction(reaction: reaction, state: state)
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
        guard let accountId, let file = self.file(), let mimetype = file.mimetype, let size = file.size else { return false }

        let capabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: accountId)

        guard NCUtils.isGif(fileType: mimetype), let maxGifSize = capabilities?.maxGifSize, maxGifSize > 0 else { return false }

        return size <= maxGifSize
    }

    public func lastMessagePreview(forOneToOneRoom: Bool = false) -> NSMutableAttributedString? {
        guard let message = messageForLastMessagePreview()?.prefix(characters: 80)
        else {return nil}

        let lastMessageAttributedString = NSMutableAttributedString()
        // Actor name (if needed)
        if let actorName = actorNameForLastMessagePreview(forOneToOneRoom: forOneToOneRoom) {
            let actorNameAttributedString = NSMutableAttributedString(string: actorName)
            lastMessageAttributedString.append(actorNameAttributedString)
        }
        // Message
        lastMessageAttributedString.append(message)

        return lastMessageAttributedString.withFont(.preferredFont(forTextStyle: .callout)).withTextColor(.secondaryLabel)
    }

    internal func actorNameForLastMessagePreview(forOneToOneRoom: Bool = false) -> String? {
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

        return actorName
    }

    public func messageForLastMessagePreview() -> NSAttributedString? {
        guard let message = self.parsedMarkdown(), message.length > 0 else { return nil }

        let messageAttributedString = NSMutableAttributedString()
        // Icon
        if let messageIconName = self.messageIconName, let messageIcon = UIImage(systemName: messageIconName) {
            // Use body font here as that is the markdown default
            let attachmentAttributedString = NSMutableAttributedString(attachment: NSTextAttachment(image: messageIcon)).withFont(.preferredFont(forTextStyle: .body))
            attachmentAttributedString.append(NSAttributedString(string: " "))
            messageAttributedString.append(attachmentAttributedString)
        }
        // Message
        messageAttributedString.append(message)

        return messageAttributedString
    }

    // MARK: - Threads

    public func isThreadOriginalMessage() -> Bool {
        return self.threadId > 0 && self.isThread && self.threadId == self.messageId
    }

    public func isThreadMessage() -> Bool {
        return self.threadId > 0 && self.isThread && self.threadId != self.messageId
    }

    // MARK: - Reactions

    public func reactionsArray() -> [NCChatReaction] {
        var reactionsArray: [NCChatReaction] = []

        // Grab message reactions
        let reactionsDict = self.reactionsDictionary()
        for reactionKey in reactionsDict.keys {
            // We need to keep this check for users who installed v14.0 (beta 1)
            if reactionKey == "self" { continue }

            let count = (reactionsDict[reactionKey] as? NSNumber)?.intValue ?? 0
            let reaction = NCChatReaction(reaction: reactionKey, count: count, userReacted: false, state: .set)
            reactionsArray.append(reaction)
        }

        // Set flag for own reactions
        for ownReaction in self.reactionsSelfArray() {
            for reaction in reactionsArray where reaction.reaction == ownReaction {
                reaction.userReacted = true
            }
        }

        // Merge with temporary reactions
        self.mergeTemporaryReactions(into: &reactionsArray)

        // Sort by reactions count
        reactionsArray.sort { $0.count > $1.count }

        return reactionsArray
    }

    // MARK: - Updating

    @objc(updateChatMessage:withChatMessage:isRoomLastMessage:)
    public static func update(_ managedChatMessage: NCChatMessage, with chatMessage: NCChatMessage, isRoomLastMessage: Bool) {
        var previewImageHeight = 0
        var previewImageWidth = 0

        // Try to keep our locally saved previewImageHeight when updating this messages with the server message
        // This happens when updating the last message of a room for example
        if let managedFile = managedChatMessage.file(), let chatFile = chatMessage.file() {
            // Only do this, if the new message does not include a height, to prevent an infinite recursion
            if managedFile.previewImageHeight > 0 && chatFile.previewImageHeight == 0 {
                previewImageHeight = managedFile.previewImageHeight
            }

            if managedFile.previewImageWidth > 0 && chatFile.previewImageWidth == 0 {
                previewImageWidth = managedFile.previewImageWidth
            }
        }

        var fileParameterDict: [AnyHashable: Any]?

        if isRoomLastMessage, managedChatMessage.file() != nil, chatMessage.file() != nil {
            // We need to keep the file information when updating from the last update message,
            // because the file information might be inaccurate on the last message
            fileParameterDict = managedChatMessage.messageParameters["file"] as? [AnyHashable: Any]
        }

        managedChatMessage.actorDisplayName = chatMessage.actorDisplayName
        managedChatMessage.actorId = chatMessage.actorId
        managedChatMessage.actorType = chatMessage.actorType
        managedChatMessage.message = chatMessage.message
        managedChatMessage.messageParametersJSONString = chatMessage.messageParametersJSONString
        managedChatMessage.timestamp = chatMessage.timestamp
        managedChatMessage.systemMessage = chatMessage.systemMessage
        managedChatMessage.isReplyable = chatMessage.isReplyable
        managedChatMessage.messageType = chatMessage.messageType
        managedChatMessage.reactionsJSONString = chatMessage.reactionsJSONString
        managedChatMessage.expirationTimestamp = chatMessage.expirationTimestamp
        managedChatMessage.isMarkdownMessage = chatMessage.isMarkdownMessage
        managedChatMessage.lastEditActorId = chatMessage.lastEditActorId
        managedChatMessage.lastEditActorType = chatMessage.lastEditActorType
        managedChatMessage.lastEditActorDisplayName = chatMessage.lastEditActorDisplayName
        managedChatMessage.lastEditTimestamp = chatMessage.lastEditTimestamp
        managedChatMessage.pinnedActorType = chatMessage.pinnedActorType
        managedChatMessage.pinnedActorId = chatMessage.pinnedActorId
        managedChatMessage.pinnedActorDisplayName = chatMessage.pinnedActorDisplayName
        managedChatMessage.pinnedUntil = chatMessage.pinnedUntil
        managedChatMessage.pinnedAt = chatMessage.pinnedAt

        if !isRoomLastMessage {
            managedChatMessage.reactionsSelfJSONString = chatMessage.reactionsSelfJSONString

            // Only update the thread data if there is any data (e.g. omit chat relay messages without thread data)
            if chatMessage.isThread, chatMessage.threadId > 0 {
                managedChatMessage.threadId = chatMessage.threadId
                managedChatMessage.isThread = chatMessage.isThread

                if let threadTitle = chatMessage.threadTitle, !threadTitle.isEmpty {
                    managedChatMessage.threadTitle = chatMessage.threadTitle
                }

                if chatMessage.threadReplies > 0 {
                    managedChatMessage.threadReplies = chatMessage.threadReplies
                }
            }
        }

        if let fileParameterDict {
            var messageParameterDict = managedChatMessage.messageParameters
            messageParameterDict["file"] = fileParameterDict

            if let jsonData = try? JSONSerialization.data(withJSONObject: messageParameterDict) {
                // Only the JSON String is stored inside of the database
                managedChatMessage.messageParametersJSONString = String(data: jsonData, encoding: .utf8)
            }
        }

        if managedChatMessage.parentId == nil, chatMessage.parentId != nil {
            managedChatMessage.parentId = chatMessage.parentId
        }

        if previewImageHeight > 0 && previewImageWidth > 0 {
            managedChatMessage.setPreviewImageSize(CGSize(width: previewImageWidth, height: previewImageHeight))
        }
    }
}

extension NCChatMessage {

    @nonobjc private func reactionsDictionary() -> [String: Any] {
        guard let data = self.reactionsJSONString?.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }

        return dict
    }

    @nonobjc private func reactionsSelfArray() -> [String] {
        guard let data = self.reactionsSelfJSONString?.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return [] }

        return array
    }

    @nonobjc private func mergeTemporaryReactions(into reactions: inout [NCChatReaction]) {
        for case let temporaryReaction as NCChatReaction in self.temporaryReactions() {
            if temporaryReaction.state == .adding || temporaryReaction.state == .added {
                self.addTemporaryReaction(temporaryReaction.reaction, into: &reactions)
            } else if temporaryReaction.state == .removing || temporaryReaction.state == .removed {
                self.removeReactionTemporarily(temporaryReaction.reaction, into: &reactions)
            }
        }
    }

    @nonobjc private func addTemporaryReaction(_ reaction: String, into reactions: inout [NCChatReaction]) {
        var includedReaction = false
        for currentReaction in reactions where currentReaction.reaction == reaction {
            // Do not need to increase the count since it was already increased on "adding" state
            if currentReaction.userReacted { return }

            currentReaction.count += 1
            currentReaction.userReacted = true
            includedReaction = true
        }

        if !includedReaction {
            let newReaction = NCChatReaction(reaction: reaction, count: 1, userReacted: true, state: .set)
            reactions.append(newReaction)
        }
    }

    @nonobjc private func removeReactionTemporarily(_ reaction: String, into reactions: inout [NCChatReaction]) {
        var removeReaction: NCChatReaction?
        for currentReaction in reactions where currentReaction.reaction == reaction && currentReaction.userReacted {
            if currentReaction.count > 1 {
                currentReaction.count -= 1
                currentReaction.userReacted = false
            } else {
                removeReaction = currentReaction
            }
        }

        if let removeReaction, let index = reactions.firstIndex(where: { $0 === removeReaction }) {
            reactions.remove(at: index)
        }
    }
}
