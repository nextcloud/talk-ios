//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Realm
import SwiftyAttributes

@objc extension NCRoom {

    public static func stringFor(notificationLevel level: NCRoomNotificationLevel) -> String {
        var levelString = ""

        switch level {
        case .always:
            levelString = NSLocalizedString("All messages", comment: "")
        case .mention:
            levelString = NSLocalizedString("@-mentions only", comment: "")
        case .never:
            levelString = NSLocalizedString("Off", comment: "")
        default:
            levelString = NSLocalizedString("Default", comment: "")
        }

        return levelString
    }

    public static func stringFor(messageExpiration expiration: NCMessageExpiration) -> String {
        var levelString = ""

        switch expiration {
        case .expiration4Weeks:
            levelString = NSLocalizedString("4 weeks", comment: "")
        case .expiration1Week:
            levelString = NSLocalizedString("1 week", comment: "")
        case .expiration1Day:
            levelString = NSLocalizedString("1 day", comment: "")
        case .expiration8Hours:
            levelString = NSLocalizedString("8 hours", comment: "")
        case .expiration1Hour:
            levelString = NSLocalizedString("1 hour", comment: "")
        case .expirationOff:
            levelString = NSLocalizedString("Off", comment: "")
        default:
            break
        }

        return levelString
    }

    public var isPublic: Bool {
        return self.type == .public
    }

    public var isFederated: Bool {
        if let remoteToken, let remoteServer {
            return !remoteToken.isEmpty && !remoteServer.isEmpty
        }

        return false
    }

    public var isEvent: Bool {
        return self.objectType == NCRoomObjectTypeEvent
    }

    @nonobjc
    public var eventTimestamps: (start: Int, end: Int)? {
        // For event rooms the objectId looks like "<startTimestamp>#<endTimestamp>"
        guard isEvent, self.objectId.contains("#") else { return nil }

        let splitTimestamps = self.objectId.components(separatedBy: "#")

        guard splitTimestamps.count == 2,
              let startTimestamp = Int(splitTimestamps[0]),
              let endTimestamp = Int(splitTimestamps[1]),
              endTimestamp >= startTimestamp
        else { return nil }

        return (startTimestamp, endTimestamp)
    }

    @nonobjc
    public var calendarEvent: CalendarEvent? {
        guard let eventTimestamps else { return nil }

        return CalendarEvent(calendarAppUrl: "", calendarUri: "", location: "", recurrenceId: "", start: eventTimestamps.start, end: eventTimestamps.end, summary: "", uri: "")
    }

    // TODO: Move to caller when migrated to swift
    public var eventStartString: String? {
        guard let start = self.eventTimestamps?.start else { return nil }

        return Date(timeIntervalSince1970: TimeInterval(start)).futureRelativeTime()
    }

    // TODO: Move to caller when migrated to swift
    public var isFutureEvent: Bool {
        return self.calendarEvent?.isFutureEvent ?? false
    }

    public var isPastEvent: Bool {
        return self.calendarEvent?.isPastEvent ?? false
    }

    public var isVisible: Bool {
        // In case we have objectType 'event', but the calendar entry was not saved, we don't have a valid timestamp,
        // in this case, we always show the room
        guard isEvent, let eventTimestamps else { return true }

        let sixteenHoursBeforeTimestamp = eventTimestamps.start - (16 * 3600)
        let nowTimestamp = Int(Date().timeIntervalSince1970)

        return nowTimestamp >= sixteenHoursBeforeTimestamp
    }

    public var supportsFederatedCalling: Bool {
        guard self.isFederated else { return false }

        let remoteCapabilitySupported = NCDatabaseManager.sharedInstance().roomHasTalkCapability(kCapabilityFederationV2, for: self)
        let localCapabilitySupported = NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityFederationV2, forAccountId: self.accountId)

        let remoteCallingEnabled = NCDatabaseManager.sharedInstance().roomTalkCapabilities(for: self)?.callEnabled ?? false
        let localCallingEnabled = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: self.accountId)?.callEnabled ?? false

        let capabilitySupported = remoteCapabilitySupported && localCapabilitySupported
        let callingEnabled = remoteCallingEnabled && localCallingEnabled

        return capabilitySupported && callingEnabled
    }

    public var supportsCalling: Bool {
        if self.isFederated, !self.supportsFederatedCalling {
            return false
        }

        return NCDatabaseManager.sharedInstance().roomTalkCapabilities(for: self)?.callEnabled ?? false &&
            self.type != .changelog && self.type != .noteToSelf
    }

    public var supportsThreading: Bool {
        if self.isFederated {
            return false
        }

        return NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityThreads, forAccountId: self.accountId) &&
        self.type != .changelog && self.type != .noteToSelf
    }

    public var supportsUpcomingEvents: Bool {
        if self.type == .formerOneToOne || self.type == .changelog || self.type == .noteToSelf {
            return false
        }

        return NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityScheduleMeeting, forAccountId: self.accountId)
    }

    public var supportsMessageExpirationModeration: Bool {
        if self.type == .formerOneToOne || self.type == .changelog {
            return false
        }

        return self.isUserOwnerOrModerator && NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityMessageExpiration)
    }

    public var supportsBanningModeration: Bool {
        let supportedType = self.type == .group || self.type == .public

        return supportedType && self.canModerate && NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityBanV1)
    }

    public var isBreakoutRoom: Bool {
        return self.objectType == NCRoomObjectTypeRoom
    }

    public var isUserOwnerOrModerator: Bool {
        return self.participantType == .owner || self.participantType == .moderator
    }

    public var canModerate: Bool {
        return self.isUserOwnerOrModerator && !self.isLockedOneToOne
    }

    public var canAddParticipants: Bool {
        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityConversationCreationAll) && self.type == .oneToOne {
            // Don't go through NCSettingsController, as that would bring too many dependencies to the extensions
            guard let capabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: accountId) else { return false }
            return capabilities.canCreate
        }

        return self.canModerate
    }

    public var isNameEditable: Bool {
        return self.canModerate && self.type != .oneToOne && self.type != .formerOneToOne
    }

    private var isLockedOneToOne: Bool {
        let lockedOneToOne = self.type == .oneToOne && NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityLockedOneToOneRooms)
        let lockedOther = self.type == .formerOneToOne || self.type == .noteToSelf

        return lockedOneToOne || lockedOther
    }

    public var userCanStartCall: Bool {
        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityStartCallFlag) && !self.canStartCall {
            return false
        }

        return true
    }

    public var hasUnreadMention: Bool {
        if self.type == .oneToOne || self.type == .formerOneToOne {
            return self.unreadMessages > 0
        }

        return self.unreadMention || self.unreadMentionDirect
    }

    public var callRecordingIsInActiveState: Bool {
        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityRecordingV1) {
            // Starting states and running states are considered active
            if self.callRecording != .stopped && self.callRecording != .failed {
                return true
            }
        }

        return false
    }

    public var deletionMessage: String {
        var message = NSLocalizedString("Do you really want to delete this conversation for everyone?", comment: "")

        if self.type == .oneToOne {
            message = String(format: NSLocalizedString("If you delete the conversation, it will also be deleted for %@", comment: ""), self.displayName)
        }

        return message
    }

    public var notificationLevelString: String {
        return NCRoom.stringFor(notificationLevel: self.notificationLevel)
    }

    public var messageExpirationString: String {
        // TODO: Check
        if let tempMessageExpiration = NCMessageExpiration(rawValue: self.messageExpiration.rawValue) {
            return NCRoom.stringFor(messageExpiration: tempMessageExpiration)
        }

        return "\(self.messageExpiration)s"
    }

    public var lastMessageString: NSMutableAttributedString? {
        var lastMessage = self.lastMessage

        if self.isFederated && lastMessage == nil {
            let lastMessageDictionary = self.lastMessageProxiedDictionary
            lastMessage = NCChatMessage(dictionary: lastMessageDictionary)
        }

        return lastMessage?.messagePreview(forOneToOneRoom: self.type == .oneToOne)
    }

    private var lastMessageProxiedDictionary: [AnyHashable: Any] {
        guard let data = self.lastMessageProxiedJSONString.data(using: .utf8),
              let jsonData = try? JSONSerialization.jsonObject(with: data) as? [AnyHashable: Any]
        else { return [:] }

        return jsonData
    }

    public var lastMessage: NCChatMessage? {
        guard let lastMessageId else { return nil }

        var unmanagedChatMessage: NCChatMessage?

        if let managedChatMessage = NCChatMessage.objects(where: "internalId = %@", lastMessageId).firstObject() {
            unmanagedChatMessage = NCChatMessage(value: managedChatMessage)
        }

        return unmanagedChatMessage
    }

    public var linkURL: String? {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: self.accountId),
              let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: self.accountId),
              let token = self.token
        else { return nil }

        var indexString = "/index.php"

        if serverCapabilities.modRewriteWorking {
            indexString = ""
        }

        return "\(account.server)\(indexString)/call/\(token)"
    }

    public var account: TalkAccount? {
        return NCDatabaseManager.sharedInstance().talkAccount(forAccountId: self.accountId)
    }

    @nonobjc
    public var parsedRoomDescription: AttributedString? {
        guard
            let account,
            NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityRoomDescription, forAccountId: account.accountId),
            let description = self.roomDescription,
            !description.isEmpty
        else { return nil }

        let attributedDescription = description.withFont(.preferredFont(forTextStyle: .body)).withTextColor(.label)

        return AttributedString(SwiftMarkdownObjCBridge.parseMarkdown(markdownString: attributedDescription))
    }

}
