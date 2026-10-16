//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// Shares database content with the app extensions without them opening the database.
///
/// iOS terminates a suspended app that holds a file lock in the app group container (0xdead10cc), which
/// Realm does during every write. So the database lives in the app's own container, the app publishes a
/// snapshot of what the extensions need to the app group, and extensions load it into an in-memory realm.
/// Changes an extension has to report back (e.g. the unread badge) are written as event files, which the
/// app merges into the database.
enum ExtensionDataStore {

    enum EventType: String {
        case unreadNotification
        case federationInvitation
    }

    struct Event {
        let id: String
        let type: EventType
        let accountId: String
        let url: URL
    }

    /// Accounts are small and published on every change, so a badge reset reaches the extensions right away.
    /// Rooms are expensive to build, so they are throttled.
    enum Part: String, CaseIterable {
        case accounts
        case rooms

        var objectClasses: [RLMObject.Type] {
            switch self {
            case .accounts:
                return [TalkAccount.self, ServerCapabilities.self]
            case .rooms:
                return [NCRoom.self, FederatedCapabilities.self]
            }
        }
    }

    // Unused by the extensions and changing on almost every refresh
    static let excludedProperties: [String: Set<String>] = [
        "TalkAccount": ["lastReceivedModifiedSince", "lastPushSubscription", "lastContactSync", "threadsLastCheckTimestamp"],
        "NCRoom": ["unreadMessages", "unreadMention", "unreadMentionDirect", "lastMessageId", "lastMessageProxiedJSONString",
                   "lastReadMessage", "lastCommonReadMessage", "lastUpdate", "hasCall", "callStartTime", "participantFlags",
                   "lastReceivedProxyHash"]
    ]

    // Allowed to be slightly outdated: a change doesn't trigger a snapshot, the next one picks it up.
    // lastActivity changes with every chat message.
    static let passiveProperties: [String: Set<String>] = [
        "NCRoom": ["lastActivity", "status", "statusIcon", "statusMessage"]
    ]

    private static let schemaVersionKey = "schemaVersion"
    private static let appliedEventIdsKey = "appliedEventIds"
    private static let eventFileExtension = "event"

    /// Replaced by tests
    static var appGroupFolderURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?.appendingPathComponent(kTalkDatabaseFolder)

    static func snapshotURL(for part: Part) -> URL? {
        return appGroupFolderURL?.appendingPathComponent("ExtensionSnapshot-\(part.rawValue).plist")
    }

    static var eventsFolderURL: URL? {
        return appGroupFolderURL?.appendingPathComponent("ExtensionEvents", isDirectory: true)
    }

    // MARK: - Events

    /// Records a change for the app to merge into its database. Doesn't change the in-memory realm.
    static func recordEvent(_ type: EventType, forAccountId accountId: String) {
        guard let eventsFolderURL else { return }

        // Encoded in the name of an empty file, so reading events is just a directory listing.
        // One file per event, so no file is ever written by two processes.
        let fileName = [type.rawValue, base64URLEncoded(accountId), UUID().uuidString].joined(separator: ".")
        let url = eventsFolderURL.appendingPathComponent(fileName).appendingPathExtension(eventFileExtension)

        do {
            try FileManager.default.createDirectory(at: eventsFolderURL, withIntermediateDirectories: true)
            // The notification service extension writes them while the device is locked
            try Data().write(to: url, options: .noFileProtection)
        } catch {
            NCLog.log("Recording extension event failed: \(error.localizedDescription)")
        }
    }

    static func pendingEvents() -> [Event] {
        return readEvents().events
    }

    private static func readEvents() -> (events: [Event], malformedURLs: [URL]) {
        guard let eventsFolderURL,
              let urls = try? FileManager.default.contentsOfDirectory(at: eventsFolderURL, includingPropertiesForKeys: nil)
        else { return ([], []) }

        var events: [Event] = []
        var malformedURLs: [URL] = []

        for url in urls {
            let components = url.deletingPathExtension().lastPathComponent.components(separatedBy: ".")

            guard url.pathExtension == eventFileExtension, components.count == 3,
                  let type = EventType(rawValue: components[0]),
                  let accountId = base64URLDecoded(components[1])
            else {
                malformedURLs.append(url)
                continue
            }

            events.append(Event(id: components[2], type: type, accountId: accountId, url: url))
        }

        return (events, malformedURLs)
    }

    // Account ids contain characters like "/" that aren't allowed in a file name
    private static func base64URLEncoded(_ string: String) -> String {
        return Data(string.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecoded(_ string: String) -> String? {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)

        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func apply(_ event: Event, in realm: RLMRealm) {
        let query = NSPredicate(format: "accountId = %@", event.accountId)
        guard let account = TalkAccount.objects(in: realm, with: query).firstObject() as? TalkAccount else { return }

        switch event.type {
        case .unreadNotification:
            account.unreadBadgeNumber += 1
            account.unreadNotification = !account.active
        case .federationInvitation:
            account.pendingFederationInvitations += 1
        }
    }

    // MARK: - Snapshot serialization

    struct Snapshot {
        let content: NSDictionary

        /// Identifies the content without keeping it in memory. Only comparable within one process, as Hasher
        /// is seeded per launch.
        let digest: Int
    }

    private static let propertyListTypes: Set<RLMPropertyType> = [.int, .bool, .float, .double, .string, .data, .date]

    /// The properties of `objectClass` that a snapshot contains
    private static func snapshotProperties(of objectClass: RLMObject.Type, in realm: RLMRealm) -> [RLMProperty] {
        let className = objectClass.className()
        let excluded = excludedProperties[className] ?? []
        let properties = realm.schema.schema(forClassName: className)?.properties ?? []

        return properties.filter {
            propertyListTypes.contains($0.type) && !$0.set && !$0.dictionary && !excluded.contains($0.name)
        }
    }

    private static func propertyListDictionary(for object: RLMObject, properties: [RLMProperty], hasher: inout Hasher) -> [String: Any] {
        var result: [String: Any] = [:]

        for property in properties {
            let value = object.value(forKey: property.name)

            if property.array {
                guard let array = value as? RLMArray<AnyObject> else {
                    hasher.combine(false)
                    continue
                }

                let elements = (0..<array.count).map { array.object(at: $0) }
                hasher.combine(true)
                hasher.combine(elements.count)
                elements.forEach { combine($0, into: &hasher) }
                result[property.name] = elements
            } else if let value, !(value is NSNull) {
                hasher.combine(true)
                combine(value, into: &hasher)
                result[property.name] = value
            } else {
                hasher.combine(false)
            }
        }

        return result
    }

    private static func combine(_ value: Any, into hasher: inout Hasher) {
        switch value {
        case let string as String:
            hasher.combine(string)
        case let number as NSNumber:
            hasher.combine(number.int64Value)
            hasher.combine(number.doubleValue)
        case let date as Date:
            hasher.combine(date.timeIntervalSince1970)
        case let data as Data:
            hasher.combine(data)
        default:
            break
        }
    }

    static func makeSnapshot(of part: Part, from realm: RLMRealm, appliedEventIds: [String] = []) -> Snapshot {
        var hasher = Hasher()
        let content = NSMutableDictionary()
        content[schemaVersionKey] = NSNumber(value: kTalkDatabaseSchemaVersion)

        if part == .accounts {
            let sortedEventIds = appliedEventIds.sorted()
            content[appliedEventIdsKey] = sortedEventIds
            hasher.combine(sortedEventIds)
        }

        for objectClass in part.objectClasses {
            let properties = snapshotProperties(of: objectClass, in: realm)
            var values: [[String: Any]] = []

            for case let object as RLMObject in objectClass.allObjects(in: realm) {
                values.append(propertyListDictionary(for: object, properties: properties, hasher: &hasher))
            }

            hasher.combine(values.count)
            content[objectClass.className()] = values
        }

        return Snapshot(content: content, digest: hasher.finalize())
    }

    /// Values for keys missing in a snapshot, i.e. nil values and excluded properties. Creating an object without
    /// a value for a non-optional property throws, and updating one keeps the old value of a missing key.
    static func defaultValues(for objectSchema: RLMObjectSchema) -> [String: Any] {
        var defaults: [String: Any] = [:]

        for property in objectSchema.properties where property.type != .linkingObjects {
            if property.array || property.set {
                defaults[property.name] = NSArray()
            } else if property.dictionary {
                defaults[property.name] = NSDictionary()
            } else if property.optional {
                defaults[property.name] = NSNull()
            } else {
                switch property.type {
                case .int, .bool, .float, .double:
                    defaults[property.name] = NSNumber(value: 0)
                case .string:
                    defaults[property.name] = ""
                case .data:
                    defaults[property.name] = NSData()
                case .date:
                    defaults[property.name] = NSDate(timeIntervalSince1970: 0)
                default:
                    // Loading would throw an exception Swift can't catch, crashing the extensions
                    assertionFailure("No default value for \(objectSchema.className).\(property.name)")
                }
            }
        }

        return defaults
    }

    /// Replaces the objects of `part` in `realm` with `snapshot`, and applies the `pendingEvents` the snapshot
    /// doesn't mark applied to the accounts. Returns false when the snapshot can't be used.
    static func load(_ snapshot: [String: Any], of part: Part, into realm: RLMRealm, pendingEvents: [Event] = []) -> Bool {
        // A snapshot of a different schema could contain values that don't fit the current one
        guard (snapshot[schemaVersionKey] as? NSNumber)?.uint64Value == kTalkDatabaseSchemaVersion else {
            NCLog.log("Extension snapshot has a different schema version, the app needs to run first")
            return false
        }

        var events: [Event] = []
        if part == .accounts {
            let appliedEventIds = Set(snapshot[appliedEventIdsKey] as? [String] ?? [])
            events = pendingEvents.filter { !appliedEventIds.contains($0.id) }
        }

        do {
            try realm.transaction {
                for objectClass in part.objectClasses {
                    let values = snapshot[objectClass.className()] as? [[String: Any]] ?? []

                    // Updated in place, so objects a running request holds stay valid
                    if let primaryKey = objectClass.primaryKey() {
                        let snapshotKeys = Set(values.compactMap { $0[primaryKey] as? String })
                        var removedObjects: [RLMObject] = []
                        for case let object as RLMObject in objectClass.allObjects(in: realm) {
                            if let key = object.value(forKey: primaryKey) as? String, !snapshotKeys.contains(key) {
                                removedObjects.append(object)
                            }
                        }
                        realm.deleteObjects(removedObjects as NSArray)
                    }

                    let defaults = realm.schema.schema(forClassName: objectClass.className()).map { defaultValues(for: $0) } ?? [:]

                    for value in values {
                        autoreleasepool {
                            _ = objectClass.createOrUpdateModified(in: realm, withValue: defaults.merging(value) { $1 })
                        }
                    }
                }

                events.forEach { apply($0, in: realm) }
            }
        } catch {
            NCLog.log("Loading extension snapshot failed: \(error.localizedDescription)")
            return false
        }

        return true
    }

    // MARK: - Loading

    private struct FileVersion: Equatable {
        let modificationDate: Date?
        let size: Int?
    }

    private static let loadLock = NSLock()

    // Guarded by loadLock, keyed by the realm loaded into
    private static var loadedRoomsVersions: [String: FileVersion] = [:]

    /// Loads the snapshot published by the app into `realm`. Returns false when there's no usable one,
    /// e.g. when the app was updated but not launched since.
    static func loadSnapshot(into realm: RLMRealm) -> Bool {
        loadLock.lock()
        defer { loadLock.unlock() }

        // Listed before reading the snapshot: the app publishes a merge before deleting its events, so each event
        // is either in this listing or marked applied in the snapshot
        let events = pendingEvents()

        // Always loaded, it's small and the badge numbers change often
        guard let accounts = readSnapshot(.accounts), load(accounts, of: .accounts, into: realm, pendingEvents: events) else {
            NCLog.log("No usable extension snapshot, the app needs to run first")
            return false
        }

        // Only loaded when the app published new ones, as large accounts have many rooms. Also when there are
        // none, in case the in-memory realm got released in between.
        let realmKey = realm.configuration.inMemoryIdentifier ?? realm.configuration.fileURL?.path ?? ""
        let roomsVersion = fileVersion(of: .rooms)
        let needsRooms = roomsVersion != loadedRoomsVersions[realmKey] || NCRoom.allObjects(in: realm).count == 0
        if needsRooms, let rooms = readSnapshot(.rooms), load(rooms, of: .rooms, into: realm) {
            loadedRoomsVersions[realmKey] = roomsVersion
        }

        return true
    }

    private static func readSnapshot(_ part: Part) -> [String: Any]? {
        guard let url = snapshotURL(for: part), let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    private static func fileVersion(of part: Part) -> FileVersion? {
        guard let path = snapshotURL(for: part)?.path,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        else { return nil }

        return FileVersion(modificationDate: attributes[.modificationDate] as? Date, size: (attributes[.size] as? NSNumber)?.intValue)
    }

    // MARK: - Publishing

    // Only accessed on the publish queue in the app
    private static var lastWrittenDigests: [URL: Int] = [:]

    private static let mergeLock = NSLock()

    /// Merged into the database, but their files are not deleted yet. Guarded by mergeLock.
    private static var mergedEventIds: Set<String> = []

    /// Merged and deleted, with the time of deletion. Guarded by mergeLock.
    /// Still marked applied for a while, as an extension may have listed the file right before its deletion.
    private static var deletedEventIds: [String: Date] = [:]
    private static let deletedEventGracePeriod: TimeInterval = 60

    /// Writes `part` of `realm` for the extensions, unless it didn't change since the last write.
    static func writeSnapshot(_ part: Part, from realm: RLMRealm) {
        guard let url = snapshotURL(for: part) else { return }

        let snapshot: Snapshot

        if part == .accounts {
            // A merge commits and records its events under this lock, so the badge numbers and the events marked
            // applied always match
            mergeLock.lock()
            realm.refresh()
            deletedEventIds = deletedEventIds.filter { -$0.value.timeIntervalSinceNow < deletedEventGracePeriod }
            let appliedEventIds = mergedEventIds.union(deletedEventIds.keys)
            snapshot = makeSnapshot(of: part, from: realm, appliedEventIds: Array(appliedEventIds))
            mergeLock.unlock()
        } else {
            realm.refresh()
            snapshot = makeSnapshot(of: part, from: realm)
        }

        guard snapshot.digest != lastWrittenDigests[url] else { return }

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: snapshot.content, format: .binary, options: 0)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // The notification service extension needs to read it while the device is locked
            try data.write(to: url, options: [.atomic, .noFileProtection])
            lastWrittenDigests[url] = snapshot.digest
        } catch {
            NCLog.log("Writing extension snapshot failed: \(error.localizedDescription)")
        }
    }

    static func hasPendingEvents() -> Bool {
        guard let eventsFolderURL else { return false }
        return !((try? FileManager.default.contentsOfDirectory(atPath: eventsFolderURL.path)) ?? []).isEmpty
    }

    /// Applies the events recorded by the extensions to `realm`, except the ones merged before.
    /// The returned events have to be passed to `finishMerge` afterwards.
    static func mergeEvents(into realm: RLMRealm) -> [Event] {
        // Nested write transactions throw, and waiting for mergeLock inside one could deadlock with a merge
        // waiting for the write lock
        guard !realm.inWriteTransaction else { return [] }

        mergeLock.lock()
        defer { mergeLock.unlock() }

        let (listedEvents, malformedURLs) = readEvents()
        malformedURLs.forEach { try? FileManager.default.removeItem(at: $0) }

        let events = listedEvents.filter { !mergedEventIds.contains($0.id) }
        guard !events.isEmpty else { return [] }

        do {
            try realm.transaction {
                events.forEach { apply($0, in: realm) }
            }
        } catch {
            NCLog.log("Merging extension events failed: \(error.localizedDescription)")
            return []
        }

        mergedEventIds.formUnion(events.map(\.id))

        return events
    }

    /// Publishes the accounts of `realm` with `events` marked as applied, so an extension doesn't count them
    /// twice, and deletes them afterwards.
    ///
    /// Events are merged at least once: if the app is killed between the commit and deleting them, they are merged
    /// again after the next launch.
    static func finishMerge(of events: [Event], from realm: RLMRealm) {
        writeSnapshot(.accounts, from: realm)

        let deletedIds = events.filter { (try? FileManager.default.removeItem(at: $0.url)) != nil }.map(\.id)

        mergeLock.lock()
        mergedEventIds.subtract(deletedIds)
        deletedIds.forEach { deletedEventIds[$0] = Date() }
        mergeLock.unlock()
    }

#if APP_EXTENSION
    /// Events are only merged by the app, into its database
    static func mergeExtensionEvents() {}
#else
    // MARK: - App side

    private static let publishQueue = DispatchQueue(label: "\(groupIdentifier).extensionSnapshot", qos: .utility)

    // Set once by `start`, read on any thread
    private static let configurationLock = NSLock()
    private static var databaseConfiguration: RLMRealmConfiguration?

    // Only accessed on the main thread
    private static var notificationTokens: [RLMNotificationToken] = []
    private static var isRoomsSnapshotScheduled = false

    /// Starts publishing snapshots of the database `realm` belongs to. Call on the main thread, with a realm
    /// that stays open.
    static func start(observing realm: RLMRealm) {
        // Unit tests run inside the app and must neither publish their data nor merge events into it
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        configurationLock.lock()
        databaseConfiguration = realm.configuration
        configurationLock.unlock()

        for part in Part.allCases {
            for objectClass in part.objectClasses {
                let token = objectClass.allObjects(in: realm).addNotificationBlock({ _, change, _ in
                    // The first call only delivers the initial state
                    guard change != nil else { return }
                    snapshotChanged(part)
                }, keyPaths: triggerKeyPaths(for: objectClass, in: realm))
                notificationTokens.append(token)
            }
        }

        _ = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            mergeExtensionEventsInBackground()
        }

        // Extensions mostly run while the app is in the background, and passive properties are only picked up by a write
        _ = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            publish(.rooms)
        }

        // Written right away, as a launch into the background might get suspended before a change triggers it
        Part.allCases.forEach { publish($0) }
        mergeExtensionEventsInBackground()
    }

    static func triggerKeyPaths(for objectClass: RLMObject.Type, in realm: RLMRealm) -> [String] {
        let className = objectClass.className()
        let ignored = (excludedProperties[className] ?? []).union(passiveProperties[className] ?? [])
        let properties = realm.schema.schema(forClassName: className)?.properties ?? []

        // Collections are left out: changing only a list is rare and can wait for the next snapshot
        return properties.filter {
            $0.type != .object && $0.type != .linkingObjects && !$0.array && !$0.set && !$0.dictionary && !ignored.contains($0.name)
        }.map(\.name)
    }

    private static func snapshotChanged(_ part: Part) {
        switch part {
        case .accounts:
            publish(.accounts)
        case .rooms:
            guard !isRoomsSnapshotScheduled else { return }
            isRoomsSnapshotScheduled = true

            // Throttled instead of debounced, so constant changes don't postpone it indefinitely
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                isRoomsSnapshotScheduled = false
                publish(.rooms)
            }
        }
    }

    private static func publish(_ part: Part) {
        let bgTask = startBackgroundTask(withName: "ExtensionSnapshot")

        publishQueue.async {
            autoreleasepool {
                if let realm = openDatabase() {
                    writeSnapshot(part, from: realm)
                }
            }
            stop(bgTask)
        }
    }

    /// Applies the changes recorded by the extensions to the database. Waits for the database write lock, so
    /// prefer `mergeExtensionEventsInBackground` where the merge doesn't have to be ordered with other writes.
    static func mergeExtensionEvents() {
        guard hasPendingEvents(), let realm = openDatabase() else { return }

        let bgTask = startBackgroundTask(withName: "MergeExtensionEvents")
        let events = mergeEvents(into: realm)

        guard !events.isEmpty else {
            stop(bgTask)
            return
        }

        // Committed synchronously, so following badge changes apply on top. Publishing can wait.
        publishQueue.async {
            autoreleasepool {
                if let realm = openDatabase() {
                    finishMerge(of: events, from: realm)
                }
            }
            stop(bgTask)
        }
    }

    /// Merges on the publish queue, so the calling thread doesn't wait for the database write lock.
    /// `completion` is called on the main thread, once the main thread realm shows the merged changes.
    static func mergeExtensionEventsInBackground(completion: (() -> Void)? = nil) {
        publishQueue.async {
            autoreleasepool {
                mergeExtensionEvents()
            }

            guard let completion else { return }

            DispatchQueue.main.async {
                RLMRealm.default().refresh()
                completion()
            }
        }
    }

    /// The database on the current thread, nil before `start`
    private static func openDatabase() -> RLMRealm? {
        configurationLock.lock()
        let configuration = databaseConfiguration
        configurationLock.unlock()

        guard let configuration else { return nil }
        return try? RLMRealm(configuration: configuration)
    }

    private static func startBackgroundTask(withName name: String) -> BGTaskHelper {
        // Ending it on expiration is up to us. An outdated snapshot is acceptable then.
        return BGTaskHelper.startBackgroundTask(withName: name) { $0.stopBackgroundTask() }
    }

    private static func stop(_ bgTask: BGTaskHelper) {
        // Expiration handlers run on the main thread, so it's only ever ended there
        DispatchQueue.main.async {
            bgTask.stopBackgroundTask()
        }
    }
#endif
}
