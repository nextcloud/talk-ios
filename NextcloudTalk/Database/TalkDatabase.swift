//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// Opens the Talk database as the default realm.
///
/// The app opens the database file in its own container. Extensions never open it, they work on the
/// snapshot the app publishes, see ExtensionDataStore.
enum TalkDatabase {

    static let objectClasses: [AnyClass] = [
        TalkAccount.self, NCRoom.self, ServerCapabilities.self, FederatedCapabilities.self,
        NCChatMessage.self, NCChatBlock.self, NCContact.self, ABContact.self, NCThread.self,
        NCConversationTag.self
    ]

#if APP_EXTENSION
    private static let keepAliveQueue = DispatchQueue(label: "\(groupIdentifier).inMemoryDatabase")

    /// An in-memory realm only exists as long as one of its instances is alive
    private static var keepAliveRealm: RLMRealm?

    static func open() {
        let configuration = RLMRealmConfiguration()
        configuration.inMemoryIdentifier = "TalkExtension"
        configuration.objectClasses = objectClasses
        RLMRealmConfiguration.setDefault(configuration)

        // Confined to its own queue and invalidated there, so it never pins an old version of the data.
        // Despite the documentation, Realm throws when a queue confined realm is opened off its queue.
        keepAliveQueue.sync {
            do {
                keepAliveRealm = try RLMRealm(configuration: configuration, queue: keepAliveQueue)
                keepAliveRealm?.invalidate()
            } catch {
                NCLog.log("Opening the in-memory database failed: \(error.localizedDescription)")
            }
        }

        _ = reload()
    }

    /// Loads the data published by the app and returns whether there is any.
    static func reload() -> Bool {
        // Released afterwards if possible, so this thread's realm doesn't keep the loaded version alive
        return autoreleasepool {
            ExtensionDataStore.loadSnapshot(into: RLMRealm.default())
        }
    }
#else
    /// Keeps the database open for the lifetime of the app, see `open`
    private static var retainedRealm: RLMRealm?

    static func open() {
        let path = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(kTalkDatabaseFolder).path

        // Create Talk database directory
        if !FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: path)

        // Set Realm configuration
        let configuration = RLMRealmConfiguration.default()
        let databaseURL = moveDatabaseOutOfAppGroupIfNeeded(to: URL(fileURLWithPath: path).appendingPathComponent(kTalkDatabaseFileName))
        configuration.fileURL = databaseURL
        configuration.schemaVersion = kTalkDatabaseSchemaVersion
        configuration.objectClasses = objectClasses
        configuration.migrationBlock = { _, _ in
            // At the very minimum we need to update the version with an empty block to indicate that the schema has been upgraded (automatically) by Realm
        }

        // Tell Realm to use this new configuration object for the default Realm
        RLMRealmConfiguration.setDefault(configuration)

        // Now that we've told Realm how to handle the schema change, opening the file
        // will automatically perform the migration
        _ = RLMRealm.default()

        // Realm caches its instances weakly, so holding one keeps the database open instead of every access
        // reopening and closing the file.
        // It has to be a main thread realm, as only those auto refresh and therefore don't pin the version
        // they were opened with, which would grow the file.
        DispatchQueue.main.async {
            // Opened from the configuration, as tests replace the default one
            guard let realm = try? RLMRealm(configuration: configuration) else { return }
            retainedRealm = realm
            ExtensionDataStore.start(observing: realm)
        }
    }

    /// The app works on the database itself, so there is nothing to reload
    static func reload() -> Bool {
        return true
    }

    /// Returns the URL to open the database at, which is the old app group location while it can't be moved.
    ///
    /// Once moved, a marker is written next to the database. Downgrading to a version that still uses the app
    /// group is not supported, the database it creates there is removed again.
    private static func moveDatabaseOutOfAppGroupIfNeeded(to databaseURL: URL) -> URL {
        let fileManager = FileManager.default
        let markerURL = databaseURL.deletingLastPathComponent().appendingPathComponent("MovedOutOfAppGroup")

        guard let legacyFolderURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?.appendingPathComponent(kTalkDatabaseFolder)
        else { return databaseURL }

        let legacyDatabaseURL = legacyFolderURL.appendingPathComponent(kTalkDatabaseFileName)

        if !fileManager.fileExists(atPath: markerURL.path), fileManager.fileExists(atPath: legacyDatabaseURL.path) {
            // Without the marker, a database here wasn't created by a completed move, so the app group one is the real one
            let folderURL = databaseURL.deletingLastPathComponent()
            let fileNames = (try? fileManager.contentsOfDirectory(atPath: folderURL.path)) ?? []
            for fileName in fileNames where fileName.hasPrefix(kTalkDatabaseFileName) {
                try? fileManager.removeItem(at: folderURL.appendingPathComponent(fileName))
            }

            do {
                try fileManager.moveItem(at: legacyDatabaseURL, to: databaseURL)
            } catch {
                // Better to keep the old location than to start with an empty database, which logs out all accounts
                NCLog.log("Moving the database out of the app group failed: \(error.localizedDescription)")
                return legacyDatabaseURL
            }
        }

        if !fileManager.fileExists(atPath: markerURL.path) {
            fileManager.createFile(atPath: markerURL.path, contents: nil)
        }

        // Lock, management and note files, plus a database a downgraded version created
        let legacyFileNames = (try? fileManager.contentsOfDirectory(atPath: legacyFolderURL.path)) ?? []
        for fileName in legacyFileNames where fileName.hasPrefix(kTalkDatabaseFileName) {
            try? fileManager.removeItem(at: legacyFolderURL.appendingPathComponent(fileName))
        }

        return databaseURL
    }
#endif
}
