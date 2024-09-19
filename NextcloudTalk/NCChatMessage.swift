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
               self.systemMessage == "message_edited"
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

        let userCanDeleteMessage = sameUser || moderatorUser

        let noTimeLimitForMessageEdit = (room.type == .noteToSelf) && NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityEditMessagesNoteToSelf, forAccountId: account.accountId)
        let editAllowedByTime = noTimeLimitForMessageEdit || (self.timestamp >= twentyFourHoursAgoTimestamp)

        return serverCanEditMessage && userCanDeleteMessage && editAllowedByTime
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

    // TODO: Should probably be an optional?
    public var systemMessageFormat: NSMutableAttributedString {
        guard let message = self.parsedMessage() else { return NSMutableAttributedString(string: "") }

        return message.withTextColor(.tertiaryLabel)
    }

    // TODO: Should probably be an optional?
    public var sendingMessage: String {
        guard var resultMessage = self.message else { return "" }

        resultMessage = resultMessage.trimmingCharacters(in: .whitespacesAndNewlines)

        for case let (key as String, value as [AnyHashable: Any]) in self.messageParameters {
            if let parameter = NCMessageParameter(dictionary: value) {
                resultMessage = resultMessage.replacingOccurrences(of: "{\(key)}", with: parameter.mentionId)
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

    public func isReactionBeingModified(_ reaction: String) -> Bool {
        return self.temporaryReactions().first(where: { ($0 as? NCChatReaction)?.reaction == reaction }) != nil
    }

    public func removeReactionFromTemporaryReactions(_ reaction: String) {
        if let removeReaction = self.temporaryReactions().first(where: { ($0 as? NCChatReaction)?.reaction == reaction }) {
            self.temporaryReactions().remove(removeReaction)
        }
    }

    public func addTemporaryReaction(_ reaction: String) {
        let temporaryReaction = NCChatReaction()
        temporaryReaction.reaction = reaction
        temporaryReaction.state = .adding
        self.temporaryReactions().add(temporaryReaction)
    }

    public func removeReactionTemporarily(_ reaction: String) {
        let temporaryReaction = NCChatReaction()
        temporaryReaction.reaction = reaction
        temporaryReaction.state = .removing
        self.temporaryReactions().add(temporaryReaction)
    }

    internal var isReferenceApiSupported: Bool {
        // Check capabilities directly, otherwise NCSettingsController introduces new dependencies in NotificationServiceExtension
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        if let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId) {
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

    public var messageIconName: String? {
        if let file = self.file() {
            if NCUtils.isImage(fileType: file.mimetype) {
                return "photo"
            } else if NCUtils.isVideo(fileType: file.mimetype) {
                return "movieclapper"
            } else if NCUtils.isVCard(fileType: file.mimetype) {
                return "person.text.rectangle"
            } else if self.isVoiceMessage {
                return "mic"
            } else if NCUtils.isAudio(fileType: file.mimetype) {
                return "music.note"
            } else {
                return "doc"
            }
        } else if poll != nil {
            return "chart.bar"
        } else if deckCard() != nil {
            return "rectangle.stack"
        } else if geoLocation() != nil {
            return "location"
        }

        return nil
    }
}
