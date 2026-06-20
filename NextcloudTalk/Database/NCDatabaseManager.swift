//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

public let kTalkDatabaseFolder = "Library/Application Support/Talk"
public let kTalkDatabaseFileName = "talk.realm"
public let kTalkDatabaseSchemaVersion: UInt64 = 90

public enum TalkCapability: String {
    case systemMessages = "system-messages"
    case notificationLevels = "notification-levels"
    case inviteGroupsAndMails = "invite-groups-and-mails"
    case lockedOneToOneRooms = "locked-one-to-one-rooms"
    case webinaryLobby = "webinary-lobby"
    case chatReadMarker = "chat-read-marker"
    case startCallFlag = "start-call-flag"
    case circlesSupport = "circles-support"
    case chatReferenceId = "chat-reference-id"
    case phonebookSearch = "phonebook-search"
    case chatReadStatus = "chat-read-status"
    case readOnlyRooms = "read-only-rooms"
    case listableRooms = "listable-rooms"
    case deleteMessages = "delete-messages"
    case callFlags = "conversation-call-flags"
    case roomDescription = "room-description"
    case tempUserAvatarAPI = "temp-user-avatar-api"
    case locationSharing = "geo-location-sharing"
    case conversationV4 = "conversation-v4"
    case sipSupport = "sip-support"
    case sipSupportNoPIN = "sip-support-nopin"
    case voiceMessage = "voice-message-sharing"
    case signalingV3 = "signaling-v3"
    case clearHistory = "clear-history"
    case directMentionFlag = "direct-mention-flag"
    case notificationCalls = "notification-calls"
    case conversationPermissions = "conversation-permissions"
    case chatUnread = "chat-unread"
    case reactions = "reactions"
    case richObjectListMedia = "rich-object-list-media"
    case richObjectDelete = "rich-object-delete"
    case unifiedSearch = "unified-search"
    case chatPermission = "chat-permission"
    case messageExpiration = "message-expiration"
    case silentSend = "silent-send"
    case silentCall = "silent-call"
    case sendCallNotification = "send-call-notification"
    case talkPolls = "talk-polls"
    case raiseHand = "raise-hand"
    case recordingV1 = "recording-v1"
    case singleConvStatus = "single-conversation-status"
    case chatKeepNotifications = "chat-keep-notifications"
    case conversationAvatars = "avatar"
    case typingIndicators = "typing-privacy"
    case publishingPermissions = "publishing-permissions"
    case remindMeLater = "remind-me-later"
    case markdownMessages = "markdown-messages"
    case noteToSelf = "note-to-self"
    case mediaCaption = "media-caption"
    case editMessages = "edit-messages"
    case deleteMessagesUnlimited = "delete-messages-unlimited"
    case federationV1 = "federation-v1"
    case federationV2 = "federation-v2"
    case chatReadLast = "chat-read-last"
    case banV1 = "ban-v1"
    case mentionPermissions = "mention-permissions"
    case editMessagesNoteToSelf = "edit-messages-note-to-self"
    case chatSummary = "chat-summary-api"
    case archivedConversationsV2 = "archived-conversations-v2"
    case callNotificationState = "call-notification-state-api"
    case forceMute = "force-mute"
    case talkPollsDrafts = "talk-polls-drafts"
    case editDraftPoll = "edit-draft-poll"
    case scheduleMeeting = "schedule-meeting"
    case conversationCreationAll = "conversation-creation-all"
    case importantConversations = "important-conversations"
    case sensitiveConversations = "sensitive-conversations"
    case threads = "threads"
    case pinnedMessages = "pinned-messages"
    case scheduleMessages = "scheduled-messages"
    case reactPermission = "react-permission"
    case botV1 = "bots-v1"

    // Talk 12.0 is the minimum required version
    public static let minimumRequired = TalkCapability.conversationV4
}

public enum NotificationsCapability: String {
    case exists = "exists"
    case testPush = "test-push"
}

// Objective-C bridge for capabilities still referenced from Objective-C code.
// These reference the Swift TalkCapability values and can be removed once those call sites are migrated to Swift.
@objcMembers public class TalkCapabilityObjC: NSObject {
    public static let singleConvStatus = TalkCapability.singleConvStatus.rawValue
    public static let conversationCreationAll = TalkCapability.conversationCreationAll.rawValue
}

public let NCDatabaseManagerPendingFederationInvitationsDidChange = "NCDatabaseManagerPendingFederationInvitationsDidChange"

public extension Notification.Name {
    static let NCDatabaseManagerRoomCapabilitiesChanged = Notification.Name(rawValue: "NCDatabaseManagerRoomCapabilitiesChangedNotification")
}

@objcMembers public class NCTranslation: NSObject {
    public var from = ""
    public var fromLabel = ""
    public var to = ""
    public var toLabel = ""
}

@objcMembers public class NCDatabaseManager: NSObject {

    private static let shared = NCDatabaseManager()

    private let capabilitiesCache = NSCache<NSString, ServerCapabilities>()

    public class func sharedInstance() -> NCDatabaseManager {
        return shared
    }

    override private init() {
        super.init()

        guard let path = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?.appendingPathComponent(kTalkDatabaseFolder).path else {
            return
        }

        // Create Talk database directory
        if !FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: path)

        // Set Realm configuration
        let configuration = RLMRealmConfiguration.default()
        let databaseURL = URL(fileURLWithPath: path).appendingPathComponent(kTalkDatabaseFileName)
        configuration.fileURL = databaseURL
        configuration.schemaVersion = kTalkDatabaseSchemaVersion
        configuration.objectClasses = [
            TalkAccount.self, NCRoom.self, ServerCapabilities.self, FederatedCapabilities.self,
            NCChatMessage.self, NCChatBlock.self, NCContact.self, ABContact.self, NCThread.self
        ]
        configuration.migrationBlock = { _, _ in
            // At the very minimum we need to update the version with an empty block to indicate that the schema has been upgraded (automatically) by Realm
        }

        // Tell Realm to use this new configuration object for the default Realm
        RLMRealmConfiguration.setDefault(configuration)

        // Now that we've told Realm how to handle the schema change, opening the file
        // will automatically perform the migration
        _ = RLMRealm.default()

#if DEBUG
        // Copy Talk DB to Documents directory
        if let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
            let dbCopyURL = URL(fileURLWithPath: documentsPath).appendingPathComponent(kTalkDatabaseFileName)
            try? FileManager.default.removeItem(at: dbCopyURL)
            try? FileManager.default.copyItem(at: databaseURL, to: dbCopyURL)
        }
#endif
    }

    // MARK: - Talk accounts

    public func numberOfAccounts() -> Int {
        return Int(TalkAccount.allObjects().count)
    }

    public func activeAccount() -> TalkAccount {
        if let managedActiveAccount = TalkAccount.objects(where: "active = true").firstObject() as? TalkAccount {
            return TalkAccount(value: managedActiveAccount)
        }
        return TalkAccount()
    }

    public func allAccounts() -> [TalkAccount] {
        var allAccounts: [TalkAccount] = []
        for case let managedAccount as TalkAccount in TalkAccount.allObjects() {
            allAccounts.append(TalkAccount(value: managedAccount))
        }
        return allAccounts
    }

    public func inactiveAccounts() -> [TalkAccount] {
        var inactiveAccounts: [TalkAccount] = []
        for case let managedInactiveAccount as TalkAccount in TalkAccount.objects(where: "active = false") {
            inactiveAccounts.append(TalkAccount(value: managedInactiveAccount))
        }
        return inactiveAccounts
    }

    public func talkAccount(forAccountId accountId: String) -> TalkAccount? {
        let query = NSPredicate(format: "accountId = %@", accountId)
        if let managedAccount = TalkAccount.objects(with: query).firstObject() as? TalkAccount {
            return TalkAccount(value: managedAccount)
        }
        return nil
    }

    public func talkAccount(forUserId userId: String, inServer server: String) -> TalkAccount? {
        let query = NSPredicate(format: "userId = %@ AND server = %@", userId, server)
        if let managedAccount = TalkAccount.objects(with: query).firstObject() as? TalkAccount {
            return TalkAccount(value: managedAccount)
        }
        return nil
    }

    public func setActiveAccountWithAccountId(_ accountId: String) {
        let realm = RLMRealm.default()
        realm.beginWriteTransaction()
        for case let account as TalkAccount in TalkAccount.allObjects() {
            account.active = false
        }
        let query = NSPredicate(format: "accountId = %@", accountId)
        let activeAccount = TalkAccount.objects(with: query).firstObject() as? TalkAccount
        activeAccount?.active = true
        try? realm.commitWriteTransaction()
        NCLog.log("Set active account to \(accountId)")
    }

    public func accountId(forUser user: String, inServer server: String) -> String {
        return "\(user)@\(server)"
    }

    public func createAccount(forUser user: String, inServer server: String) {
        let account = TalkAccount()
        account.accountId = accountId(forUser: user, inServer: server)
        account.server = server
        account.user = user

        let realm = RLMRealm.default()
        try? realm.transaction {
            realm.add(account)
        }
    }

    public func removeAccount(withAccountId accountId: String) {
        let realm = RLMRealm.default()
        realm.beginWriteTransaction()
        let isLastAccount = numberOfAccounts() == 1
        let query = NSPredicate(format: "accountId = %@", accountId)
        if let removeAccount = TalkAccount.objects(with: query).firstObject() as? TalkAccount {
            realm.delete(removeAccount)
        }
        if let serverCapabilities = ServerCapabilities.objects(with: query).firstObject() as? ServerCapabilities {
            realm.delete(serverCapabilities)
            capabilitiesCache.removeObject(forKey: accountId as NSString)
        }
        realm.deleteObjects(NCRoom.objects(with: query))
        realm.deleteObjects(NCChatMessage.objects(with: query))
        realm.deleteObjects(NCChatBlock.objects(with: query))
        realm.deleteObjects(NCThread.objects(with: query))
        realm.deleteObjects(NCContact.objects(with: query))
        realm.deleteObjects(FederatedCapabilities.objects(with: query))
        if isLastAccount {
            realm.deleteObjects(ABContact.allObjects())
        }
        try? realm.commitWriteTransaction()
    }

    public func removeStoredMessages(forAccountId accountId: String) {
        let realm = RLMRealm.default()
        realm.beginWriteTransaction()
        let query = NSPredicate(format: "accountId = %@", accountId)
        realm.deleteObjects(NCChatMessage.objects(with: query))
        realm.deleteObjects(NCChatBlock.objects(with: query))
        realm.deleteObjects(NCThread.objects(with: query))
        try? realm.commitWriteTransaction()
    }

    public func increaseUnreadBadgeNumber(forAccountId accountId: String) {
        let realm = RLMRealm.default()
        realm.beginWriteTransaction()
        let query = NSPredicate(format: "accountId = %@", accountId)
        if let account = TalkAccount.objects(with: query).firstObject() as? TalkAccount {
            account.unreadBadgeNumber += 1
            account.unreadNotification = true
        }
        try? realm.commitWriteTransaction()
    }

    public func decreaseUnreadBadgeNumber(forAccountId accountId: String) {
        let realm = RLMRealm.default()
        realm.beginWriteTransaction()
        let query = NSPredicate(format: "accountId = %@", accountId)
        if let account = TalkAccount.objects(with: query).firstObject() as? TalkAccount {
            account.unreadBadgeNumber = (account.unreadBadgeNumber > 0) ? account.unreadBadgeNumber - 1 : 0
            account.unreadNotification = (account.unreadBadgeNumber > 0) ? account.unreadNotification : false
        }
        try? realm.commitWriteTransaction()
    }

    public func resetUnreadBadgeNumber(forAccountId accountId: String) {
        let bgTask = BGTaskHelper.startBackgroundTask(withName: "resetUnreadBadgeNumberForAccountId", expirationHandler: nil)
        let realm = RLMRealm.default()
        realm.beginWriteTransaction()
        let query = NSPredicate(format: "accountId = %@", accountId)
        if let account = TalkAccount.objects(with: query).firstObject() as? TalkAccount {
            account.unreadBadgeNumber = 0
            account.unreadNotification = false
        }
        try? realm.commitWriteTransaction()
        bgTask.stopBackgroundTask()
    }

    public func numberOfInactiveAccountsWithUnreadNotifications() -> Int {
        return Int(TalkAccount.objects(where: "active = false AND unreadNotification = true").count)
    }

    public func numberOfUnreadNotifications() -> Int {
        // Make sure that the data on this thread is up to date.
        // Failing to do so might result in inaccurate badge numbers when they were updated on a different thread
        RLMRealm.default().refresh()

        var unreadNotifications = 0
        for case let account as TalkAccount in TalkAccount.allObjects() {
            unreadNotifications += account.unreadBadgeNumber
        }
        return unreadNotifications
    }

    public func removeUnreadNotificationForInactiveAccounts() {
        let realm = RLMRealm.default()
        realm.beginWriteTransaction()
        for case let account as TalkAccount in TalkAccount.allObjects() {
            account.unreadNotification = false
        }
        try? realm.commitWriteTransaction()
    }

    public func updateTalkConfigurationHash(forAccountId accountId: String, withHash hash: String) {
        let bgTask = BGTaskHelper.startBackgroundTask(withName: "updateTalkConfigurationHashForAccountId", expirationHandler: nil)
        let realm = RLMRealm.default()
        realm.beginWriteTransaction()
        let query = NSPredicate(format: "accountId = %@", accountId)
        if let account = TalkAccount.objects(with: query).firstObject() as? TalkAccount {
            account.lastReceivedConfigurationHash = hash
        }
        try? realm.commitWriteTransaction()
        bgTask.stopBackgroundTask()
    }

    public func updateLastModifiedSince(forAccountId accountId: String, with modifiedSince: String) {
        let bgTask = BGTaskHelper.startBackgroundTask(withName: "updateLastModifiedSinceForAccountId", expirationHandler: nil)
        let realm = RLMRealm.default()
        realm.beginWriteTransaction()
        let query = NSPredicate(format: "accountId = %@", accountId)
        if let account = TalkAccount.objects(with: query).firstObject() as? TalkAccount {
            account.lastReceivedModifiedSince = modifiedSince
        }
        try? realm.commitWriteTransaction()
        bgTask.stopBackgroundTask()
    }

    public func updateHasThreads(forAccountId accountId: String, with hasThreads: Bool) {
        let bgTask = BGTaskHelper.startBackgroundTask(withName: "updateHasThreadsForAccountId", expirationHandler: nil)
        let realm = RLMRealm.default()
        realm.beginWriteTransaction()
        let query = NSPredicate(format: "accountId = %@", accountId)
        if let account = TalkAccount.objects(with: query).firstObject() as? TalkAccount {
            account.hasThreads = hasThreads
        }
        try? realm.commitWriteTransaction()
        bgTask.stopBackgroundTask()

        let userInfo: [String: Any] = ["accountId": accountId, "hasThreads": hasThreads]
        NotificationCenter.default.post(name: .NCUserHasThreadsFlagUpdated, object: self, userInfo: userInfo)
    }

    public func updateThreadsLastCheckTimestamp(forAccountId accountId: String, with lastCheckTimestamp: Int) {
        let bgTask = BGTaskHelper.startBackgroundTask(withName: "updateHasThreadsLastCheckTimestampForAccountId", expirationHandler: nil)
        let realm = RLMRealm.default()
        realm.beginWriteTransaction()
        let query = NSPredicate(format: "accountId = %@", accountId)
        if let account = TalkAccount.objects(with: query).firstObject() as? TalkAccount {
            account.threadsLastCheckTimestamp = lastCheckTimestamp
        }
        try? realm.commitWriteTransaction()
        bgTask.stopBackgroundTask()
    }

    // MARK: - Rooms

    public func room(withToken token: String, forAccountId accountId: String) -> NCRoom? {
        let query = NSPredicate(format: "token = %@ AND accountId = %@", token, accountId)
        if let managedRoom = NCRoom.objects(with: query).firstObject() as? NCRoom {
            return NCRoom(value: managedRoom)
        }
        return nil
    }

    public func room(withInternalId internalId: String) -> NCRoom? {
        let query = NSPredicate(format: "internalId = %@", internalId)
        if let managedRoom = NCRoom.objects(with: query).firstObject() as? NCRoom {
            return NCRoom(value: managedRoom)
        }
        return nil
    }

    // MARK: - Talk capabilities

    private func setTalkCapabilities(_ capabilitiesDict: [AnyHashable: Any], onTalkCapabilitiesObject capabilities: TalkCapabilities) {
        let config = capabilitiesDict["config"] as? [String: Any]

        capabilities.setValue(capabilitiesDict["features"], forKey: "talkCapabilities")
        capabilities.hasTranslationProviders = ((config?["chat"] as? [String: Any])?["has-translation-providers"] as? NSNumber)?.boolValue ?? false
        capabilities.attachmentsAllowed = ((config?["attachments"] as? [String: Any])?["allowed"] as? NSNumber)?.boolValue ?? false
        capabilities.attachmentsFolder = (config?["attachments"] as? [String: Any])?["folder"] as? String ?? ""
        capabilities.conversationSubfoldersEnabled = ((config?["attachments"] as? [String: Any])?["conversation-subfolders"] as? NSNumber)?.boolValue ?? false
        capabilities.talkVersion = capabilitiesDict["version"] as? String ?? ""

        // Call capabilities
        let callConfig = config?["call"] as? [String: Any]
        capabilities.callEnabled = (callConfig?["enabled"] as? NSNumber)?.boolValue ?? true
        capabilities.recordingEnabled = (callConfig?["recording"] as? NSNumber)?.boolValue ?? false
        capabilities.setValue(callConfig?["supported-reactions"] ?? [], forKey: "callReactions")
        capabilities.e2eeCallsEnabled = (callConfig?["end-to-end-encryption"] as? NSNumber)?.boolValue ?? false

        // Conversations capabilities
        let conversationsConfig = config?["conversations"] as? [String: Any]
        capabilities.canCreate = (conversationsConfig?["can-create"] as? NSNumber)?.boolValue ?? true
        capabilities.descriptionLength = (conversationsConfig?["description-length"] as? NSNumber)?.intValue ?? 500

        if let retentionEvent = (conversationsConfig?["retention-event"] as? NSNumber)?.intValue {
            capabilities.retentionEvent = retentionEvent
        }
        if let retentionPhone = (conversationsConfig?["retention-phone"] as? NSNumber)?.intValue {
            capabilities.retentionPhone = retentionPhone
        }
        if let retentionInstantMeetings = (conversationsConfig?["retention-instant-meetings"] as? NSNumber)?.intValue {
            capabilities.retentionInstantMeetings = retentionInstantMeetings
        }

        if let sortOrder = conversationsConfig?["sort-order"] as? String {
            capabilities.roomsSortOrder = (sortOrder == "alphabetical" ? NCRoomSortOrder.alphabetical : .activity).rawValue
        } else {
            capabilities.roomsSortOrder = NCRoomSortOrder.unsupported.rawValue
        }

        if let groupMode = conversationsConfig?["group-mode"] as? String {
            switch groupMode {
            case "group-first":
                capabilities.roomsGroupMode = NCRoomGroupMode.groupFirst.rawValue
            case "private-first":
                capabilities.roomsGroupMode = NCRoomGroupMode.privateFirst.rawValue
            default:
                capabilities.roomsGroupMode = NCRoomGroupMode.none.rawValue
            }
        } else {
            capabilities.roomsGroupMode = NCRoomGroupMode.unsupported.rawValue
        }

        // Chat capabilities
        let chatConfig = config?["chat"] as? [String: Any]
        capabilities.readStatusPrivacy = (chatConfig?["read-privacy"] as? NSNumber)?.boolValue ?? false
        capabilities.chatMaxLength = (chatConfig?["max-length"] as? NSNumber)?.intValue ?? 0
        capabilities.typingPrivacy = (chatConfig?["typing-privacy"] as? NSNumber)?.boolValue ?? true
        capabilities.summaryThreshold = (chatConfig?["summary-threshold"] as? NSNumber)?.intValue ?? 0

        // Translations
        if let translations = chatConfig?["translations"] as? [Any],
           let jsonData = try? JSONSerialization.data(withJSONObject: translations),
           let translationsString = String(data: jsonData, encoding: .utf8) {
            capabilities.translations = translationsString
        }

        // Federation capabilities
        let federationConfig = config?["federation"] as? [String: Any]
        capabilities.federationEnabled = (federationConfig?["enabled"] as? NSNumber)?.boolValue ?? false
        capabilities.federationIncomingEnabled = (federationConfig?["incoming-enabled"] as? NSNumber)?.boolValue ?? false
        capabilities.federationOutgoingEnabled = (federationConfig?["outgoing-enabled"] as? NSNumber)?.boolValue ?? false
        capabilities.federationOnlyTrustedServers = (federationConfig?["only-trusted-servers"] as? NSNumber)?.boolValue ?? false

        // Previews
        let previewConfig = config?["previews"] as? [String: Any]
        if let maxGifSize = (previewConfig?["max-gif-size"] as? NSNumber)?.intValue {
            capabilities.maxGifSize = maxGifSize
        }
    }

    // MARK: - Federated capabilities

    public func federatedCapabilities(forAccountId accountId: String, remoteServer: String, roomToken: String) -> FederatedCapabilities? {
        let query = NSPredicate(format: "accountId = %@ AND remoteServer = %@ AND roomToken = %@", accountId, remoteServer, roomToken)
        if let managedFederatedCapabilities = FederatedCapabilities.objects(with: query).firstObject() as? FederatedCapabilities {
            return FederatedCapabilities(value: managedFederatedCapabilities)
        }
        return nil
    }

    public func setFederatedCapabilities(_ federatedCapabilitiesDict: [AnyHashable: Any], forAccountId accountId: String, remoteServer: String, roomToken: String, withProxyHash proxyHash: String) {
        let federatedCapabilities = FederatedCapabilities()
        federatedCapabilities.internalId = "\(accountId)@\(remoteServer)@\(roomToken)"
        federatedCapabilities.accountId = accountId
        federatedCapabilities.remoteServer = remoteServer
        federatedCapabilities.roomToken = roomToken

        setTalkCapabilities(federatedCapabilitiesDict, onTalkCapabilitiesObject: federatedCapabilities)

        let realm = RLMRealm.default()
        try? realm.transaction {
            realm.addOrUpdate(federatedCapabilities)

            // Update the hash
            let query = NSPredicate(format: "token = %@ AND accountId = %@", roomToken, accountId)
            if let managedRoom = NCRoom.objects(with: query).firstObject() as? NCRoom {
                managedRoom.lastReceivedProxyHash = proxyHash
            }

            let userInfo: [String: Any] = ["accountId": accountId, "roomToken": roomToken]
            NotificationCenter.default.post(name: .NCDatabaseManagerRoomCapabilitiesChanged, object: self, userInfo: userInfo)
        }
    }

    // MARK: - Room capabilities

    public func roomHasTalkCapability(_ capability: String, for room: NCRoom) -> Bool {
        if !room.isFederated {
            return serverHasTalkCapability(capability, forAccountId: room.accountId)
        }

        guard let federatedCapabilities = federatedCapabilities(forAccountId: room.accountId, remoteServer: room.remoteServer, roomToken: room.token) else {
            return false
        }

        let talkFeatures = federatedCapabilities.talkCapabilities.value(forKey: "self") as? [String] ?? []
        return talkFeatures.contains(capability)
    }

    public func roomTalkCapabilities(for room: NCRoom) -> TalkCapabilities? {
        if room.isFederated {
            if let federatedCapabilities = federatedCapabilities(forAccountId: room.accountId, remoteServer: room.remoteServer, roomToken: room.token) {
                return TalkCapabilities(value: federatedCapabilities)
            }
            return nil
        }

        if let serverCapabilities = serverCapabilities(forAccountId: room.accountId) {
            return TalkCapabilities(value: serverCapabilities)
        }

        return nil
    }

    // MARK: - Server capabilities

    public func serverCapabilities() -> ServerCapabilities? {
        return serverCapabilities(forAccountId: activeAccount().accountId)
    }

    public func serverCapabilities(forAccountId accountId: String) -> ServerCapabilities? {
        if let cachedCapabilities = capabilitiesCache.object(forKey: accountId as NSString) {
            return cachedCapabilities
        }

        let query = NSPredicate(format: "accountId = %@", accountId)
        if let managedServerCapabilities = ServerCapabilities.objects(with: query).firstObject() as? ServerCapabilities {
            let unmanagedServerCapabilities = ServerCapabilities(value: managedServerCapabilities)
            capabilitiesCache.setObject(unmanagedServerCapabilities, forKey: accountId as NSString)
            return unmanagedServerCapabilities
        }
        return nil
    }

    public func setServerCapabilities(_ serverCapabilities: [AnyHashable: Any], forAccountId accountId: String) {
        let serverCaps = serverCapabilities["capabilities"] as? [String: Any]
        let coreCaps = serverCaps?["core"] as? [String: Any]
        let version = serverCapabilities["version"] as? [String: Any]
        let themingCaps = serverCaps?["theming"] as? [String: Any]
        let talkCaps = serverCaps?["spreed"] as? [AnyHashable: Any]
        let userStatusCaps = serverCaps?["user_status"] as? [String: Any]
        let provisioningAPICaps = serverCaps?["provisioning_api"] as? [String: Any]
        let guestsCaps = serverCaps?["guests"] as? [String: Any]
        let notificationsCaps = serverCaps?["notifications"] as? [String: Any]
        let davCaps = serverCaps?["dav"] as? [String: Any]
        let passwordPolicyCaps = serverCaps?["password_policy"] as? [String: Any]

        let capabilities = ServerCapabilities()
        capabilities.accountId = accountId
        capabilities.name = themingCaps?["name"] as? String ?? ""
        capabilities.slogan = themingCaps?["slogan"] as? String ?? ""
        capabilities.url = themingCaps?["url"] as? String ?? ""
        capabilities.logo = themingCaps?["logo"] as? String ?? ""
        capabilities.color = themingCaps?["color"] as? String ?? ""
        capabilities.colorElement = themingCaps?["color-element"] as? String ?? ""
        capabilities.colorElementBright = themingCaps?["color-element-bright"] as? String ?? ""
        capabilities.colorElementDark = themingCaps?["color-element-dark"] as? String ?? ""
        capabilities.colorText = themingCaps?["color-text"] as? String ?? ""
        capabilities.background = themingCaps?["background"] as? String ?? ""
        capabilities.backgroundDefault = (themingCaps?["background-default"] as? NSNumber)?.boolValue ?? false
        capabilities.backgroundPlain = (themingCaps?["background-plain"] as? NSNumber)?.boolValue ?? false
        capabilities.version = version?["string"] as? String ?? ""
        capabilities.versionMajor = (version?["major"] as? NSNumber)?.intValue ?? 0
        capabilities.versionMinor = (version?["minor"] as? NSNumber)?.intValue ?? 0
        capabilities.versionMicro = (version?["micro"] as? NSNumber)?.intValue ?? 0
        capabilities.edition = version?["edition"] as? String ?? ""
        capabilities.userStatus = (userStatusCaps?["enabled"] as? NSNumber)?.boolValue ?? false
        capabilities.userStatusSupportsBusy = (userStatusCaps?["supports_busy"] as? NSNumber)?.boolValue ?? false
        capabilities.extendedSupport = (version?["extendedSupport"] as? NSNumber)?.boolValue ?? false
        capabilities.accountPropertyScopesVersion2 = (provisioningAPICaps?["AccountPropertyScopesVersion"] as? NSNumber)?.intValue == 2
        capabilities.accountPropertyScopesFederationEnabled = (provisioningAPICaps?["AccountPropertyScopesFederationEnabled"] as? NSNumber)?.boolValue ?? false
        capabilities.accountPropertyScopesFederatedEnabled = (provisioningAPICaps?["AccountPropertyScopesFederatedEnabled"] as? NSNumber)?.boolValue ?? false
        capabilities.accountPropertyScopesPublishedEnabled = (provisioningAPICaps?["AccountPropertyScopesPublishedEnabled"] as? NSNumber)?.boolValue ?? false
        capabilities.guestsAppEnabled = (guestsCaps?["enabled"] as? NSNumber)?.boolValue ?? false
        capabilities.referenceApiSupported = (coreCaps?["reference-api"] as? NSNumber)?.boolValue ?? false
        capabilities.modRewriteWorking = (coreCaps?["mod-rewrite-working"] as? NSNumber)?.boolValue ?? false
        capabilities.absenceSupported = (davCaps?["absence-supported"] as? NSNumber)?.boolValue ?? false
        capabilities.absenceReplacementSupported = (davCaps?["absence-replacement"] as? NSNumber)?.boolValue ?? false
        capabilities.setValue(notificationsCaps?["ocs-endpoints"], forKey: "notificationsCapabilities")
        capabilities.passwordPolicyGenerateAPIEndpoint = (passwordPolicyCaps?["api"] as? [String: Any])?["generate"] as? String ?? ""
        capabilities.passwordPolicyValidateAPIEndpoint = (passwordPolicyCaps?["api"] as? [String: Any])?["validate"] as? String ?? ""

        if let sharingPolicy = (passwordPolicyCaps?["policies"] as? [String: Any])?["sharing"] as? [String: Any] {
            capabilities.passwordPolicyMinLength = (sharingPolicy["minLength"] as? NSNumber)?.intValue ?? 0
        } else {
            capabilities.passwordPolicyMinLength = (passwordPolicyCaps?["minLength"] as? NSNumber)?.intValue ?? 0
        }

        if let talkCaps {
            setTalkCapabilities(talkCaps, onTalkCapabilitiesObject: capabilities)
        }

        let realm = RLMRealm.default()
        try? realm.transaction {
            realm.addOrUpdate(capabilities)
        }

        let unmanagedServerCapabilities = ServerCapabilities(value: capabilities)
        capabilitiesCache.setObject(unmanagedServerCapabilities, forKey: accountId as NSString)
    }

    public func serverHasTalkCapability(_ capability: String) -> Bool {
        return serverHasTalkCapability(capability, forAccountId: activeAccount().accountId)
    }

    public func serverHasTalkCapability(_ capability: String, forAccountId accountId: String) -> Bool {
        guard let serverCapabilities = serverCapabilities(forAccountId: accountId) else {
            return false
        }
        let talkFeatures = serverCapabilities.talkCapabilities.value(forKey: "self") as? [String] ?? []
        return talkFeatures.contains(capability)
    }

    public func serverHasNotificationsCapability(_ capability: String, forAccountId accountId: String) -> Bool {
        guard let serverCapabilities = serverCapabilities(forAccountId: accountId) else {
            return false
        }
        let notificationsFeatures = serverCapabilities.notificationsCapabilities.value(forKey: "self") as? [String] ?? []
        return notificationsFeatures.contains(capability)
    }

    public func serverCanInviteFederatedUsersforAccountId(_ accountId: String) -> Bool {
        if let serverCapabilities = serverCapabilities(forAccountId: accountId), serverHasTalkCapability(.federationV1, forAccountId: accountId) {
            return serverCapabilities.federationEnabled && serverCapabilities.federationOutgoingEnabled
        }
        return false
    }

    public func setExternalSignalingServerVersion(_ version: String, forAccountId accountId: String) {
        let realm = RLMRealm.default()
        try? realm.transaction {
            let query = NSPredicate(format: "accountId = %@", accountId)
            if let managedServerCapabilities = ServerCapabilities.objects(with: query).firstObject() as? ServerCapabilities,
               managedServerCapabilities.externalSignalingServerVersion != version {
                managedServerCapabilities.externalSignalingServerVersion = version

                let unmanagedServerCapabilities = ServerCapabilities(value: managedServerCapabilities)
                capabilitiesCache.setObject(unmanagedServerCapabilities, forKey: accountId as NSString)
            }
        }
    }

    // MARK: - Translations

    public func hasAvailableTranslations(forAccountId accountId: String) -> Bool {
        return hasTranslationProviders(forAccountId: accountId) || !availableTranslations(forAccountId: accountId).isEmpty
    }

    public func hasTranslationProviders(forAccountId accountId: String) -> Bool {
        return serverCapabilities(forAccountId: accountId)?.hasTranslationProviders ?? false
    }

    public func availableTranslations(forAccountId accountId: String) -> [NCTranslation] {
        guard let serverCapabilities = serverCapabilities(forAccountId: accountId) else {
            return []
        }
        let translationsArray = translationsArray(fromJSONString: serverCapabilities.translations)
        return translations(fromTranslationsArray: translationsArray)
    }

    private func translationsArray(fromJSONString jsonString: String?) -> [Any] {
        guard let data = jsonString?.data(using: .utf8) else {
            return []
        }
        do {
            return try JSONSerialization.jsonObject(with: data) as? [Any] ?? []
        } catch {
            NSLog("Error retrieving translations JSON data: %@", error.localizedDescription)
            return []
        }
    }

    public func translations(fromTranslationsArray translations: [Any]) -> [NCTranslation] {
        var availableTranslations: [NCTranslation] = []
        for case let translationDict as [String: Any] in translations {
            let translation = NCTranslation()
            translation.from = translationDict["from"] as? String ?? ""
            translation.fromLabel = translationDict["fromLabel"] as? String ?? ""
            translation.to = translationDict["to"] as? String ?? ""
            translation.toLabel = translationDict["toLabel"] as? String ?? ""
            availableTranslations.append(translation)
        }
        return availableTranslations
    }

    // MARK: - Federation invitations

    public func increasePendingFederationInvitation(forAccountId accountId: String) {
        let realm = RLMRealm.default()
        realm.beginWriteTransaction()
        let query = NSPredicate(format: "accountId = %@", accountId)
        if let account = TalkAccount.objects(with: query).firstObject() as? TalkAccount {
            account.pendingFederationInvitations += 1
        }
        try? realm.commitWriteTransaction()
    }

    public func decreasePendingFederationInvitation(forAccountId accountId: String) {
        let realm = RLMRealm.default()
        realm.beginWriteTransaction()
        let query = NSPredicate(format: "accountId = %@", accountId)
        if let account = TalkAccount.objects(with: query).firstObject() as? TalkAccount {
            account.pendingFederationInvitations = (account.pendingFederationInvitations > 0) ? account.pendingFederationInvitations - 1 : 0
        }
        try? realm.commitWriteTransaction()

        NotificationCenter.default.post(name: NSNotification.Name(rawValue: NCDatabaseManagerPendingFederationInvitationsDidChange), object: self, userInfo: nil)
    }

    public func setPendingFederationInvitationForAccountId(_ accountId: String, with numberOfPendingInvitations: Int) {
        let realm = RLMRealm.default()
        realm.beginWriteTransaction()
        let query = NSPredicate(format: "accountId = %@", accountId)
        if let account = TalkAccount.objects(with: query).firstObject() as? TalkAccount {
            account.pendingFederationInvitations = numberOfPendingInvitations
        }
        try? realm.commitWriteTransaction()

        NotificationCenter.default.post(name: NSNotification.Name(rawValue: NCDatabaseManagerPendingFederationInvitationsDidChange), object: self, userInfo: nil)
    }
}

@objc public extension NCDatabaseManager {

    func increaseEmojiUsage(forEmoji emojiString: String, forAccount accountId: String) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId) else { return }
        var newData: [String: Int]?

        if let data = account.frequentlyUsedEmojisJSONString.data(using: .utf8),
           var emojiData = try? JSONSerialization.jsonObject(with: data) as? [String: Int] {

            if let currentEmojiCount = emojiData[emojiString] {
                emojiData[emojiString] = currentEmojiCount + 1
            } else {
                emojiData[emojiString] = 1
            }

            newData = emojiData
        } else {
            // No existing data, start new
            newData = [emojiString: 1]
        }

        guard let newData, let jsonData = try? JSONSerialization.data(withJSONObject: newData),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else { return }

        let realm = RLMRealm.default()

        try? realm.transaction {
            if let managedTalkAccount = TalkAccount.objects(where: "accountId = %@", account.accountId).firstObject() as? TalkAccount {
                managedTalkAccount.frequentlyUsedEmojisJSONString = jsonString
            }
        }
    }

    // MARK: - Rooms

    func roomsForAccountId(_ accountId: String, withRealm realm: RLMRealm?) -> [NCRoom] {
        let query = NSPredicate(format: "accountId = %@", accountId)
        var managedRooms: RLMResults<AnyObject>

        if let realm {
            managedRooms = NCRoom.objects(in: realm, with: query)
        } else {
            managedRooms = NCRoom.objects(with: query)
        }

        // Create an unmanaged copy of the rooms
        var unmanagedRooms: [NCRoom] = []

        for case let managedRoom as NCRoom in managedRooms {
            if managedRoom.isBreakoutRoom, managedRoom.lobbyState == .moderatorsOnly {
                continue
            }

            unmanagedRooms.append(NCRoom(value: managedRoom))
        }

        // Sort rooms
        let capabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: accountId)
        var groupMode: NCRoomGroupMode = .none
        var sortOrder: NCRoomSortOrder = .activity

        if let capabilities {
            groupMode = NCRoomGroupMode(rawValue: capabilities.roomsGroupMode) ?? groupMode
            sortOrder = NCRoomSortOrder(rawValue: capabilities.roomsSortOrder) ?? sortOrder
        }

        unmanagedRooms.sortRooms(withGroupMode: groupMode, withSortOrder: sortOrder)

        return unmanagedRooms
    }
}

// MARK: - Type-safe capability checks

public extension NCDatabaseManager {

    func serverHasTalkCapability(_ capability: TalkCapability) -> Bool {
        return serverHasTalkCapability(capability.rawValue)
    }

    func serverHasTalkCapability(_ capability: TalkCapability, forAccountId accountId: String) -> Bool {
        return serverHasTalkCapability(capability.rawValue, forAccountId: accountId)
    }

    func serverHasNotificationsCapability(_ capability: NotificationsCapability, forAccountId accountId: String) -> Bool {
        return serverHasNotificationsCapability(capability.rawValue, forAccountId: accountId)
    }

    func roomHasTalkCapability(_ capability: TalkCapability, for room: NCRoom) -> Bool {
        return roomHasTalkCapability(capability.rawValue, for: room)
    }
}
