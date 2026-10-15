//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

// The test realm of TestBaseRealm plays the app database, a second in-memory realm plays an extension
final class UnitExtensionDataStore: TestBaseRealm {

    private var originalAppGroupFolderURL: URL?
    private var folderURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        originalAppGroupFolderURL = ExtensionDataStore.appGroupFolderURL
        folderURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        ExtensionDataStore.appGroupFolderURL = folderURL
    }

    override func tearDownWithError() throws {
        ExtensionDataStore.appGroupFolderURL = originalAppGroupFolderURL
        try? FileManager.default.removeItem(at: folderURL)

        try super.tearDownWithError()
    }

    private func makeExtensionRealm() throws -> RLMRealm {
        let configuration = RLMRealmConfiguration()
        configuration.inMemoryIdentifier = UUID().uuidString
        return try RLMRealm(configuration: configuration)
    }

    // Goes through the same serialization as the files the extensions read
    private func snapshot(of part: ExtensionDataStore.Part) throws -> [String: Any] {
        let snapshot = ExtensionDataStore.makeSnapshot(of: part, from: realm).content
        let data = try PropertyListSerialization.data(fromPropertyList: snapshot, format: .binary, options: 0)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    private func load(into extensionRealm: RLMRealm) throws {
        for part in ExtensionDataStore.Part.allCases {
            XCTAssertTrue(ExtensionDataStore.load(try snapshot(of: part), of: part, into: extensionRealm))
        }
    }

    private func publish() {
        for part in ExtensionDataStore.Part.allCases {
            ExtensionDataStore.writeSnapshot(part, from: realm)
        }
    }

    private func merge() {
        let events = ExtensionDataStore.mergeEvents(into: realm)
        ExtensionDataStore.finishMerge(of: events, from: realm)
    }

    private func badgeNumber(in realm: RLMRealm, forAccountId accountId: String = TestBaseRealm.fakeAccountId) -> Int {
        return TalkAccount.object(in: realm, forPrimaryKey: accountId)?.unreadBadgeNumber ?? -1
    }

    private func addInactiveAccount(withAccountId accountId: String) throws {
        let account = TalkAccount()
        account.accountId = accountId
        try realm.transaction {
            realm.add(account)
        }
    }

    // MARK: - Snapshot

    func testSnapshotRoundTrip() throws {
        let account = try XCTUnwrap(TalkAccount.object(forPrimaryKey: TestBaseRealm.fakeAccountId))
        try realm.transaction {
            account.userDisplayName = "Display Name"
            account.userPublicKey = "publicKey"
            account.unreadBadgeNumber = 3
            account.lastReceivedModifiedSince = "1760000000"
            account.groupIds.addObjects(["admin", "staff"] as NSArray)
        }

        addRoom(withToken: "token", withName: "name") { room in
            room.displayName = "Room"
            room.lastActivity = 1234
            room.unreadMessages = 5
            room.isFavorite = true
        }

        updateCapabilities { capabilities in
            capabilities.versionMajor = 32
            capabilities.attachmentsFolder = "/Talk"
            capabilities.talkCapabilities.addObjects(["chat-v2", "media-caption"] as NSArray)
        }

        let accountValues = try XCTUnwrap((try snapshot(of: .accounts)["TalkAccount"] as? [[String: Any]])?.first)
        // Excluded, as it changes on every rooms refresh
        XCTAssertNil(accountValues["lastReceivedModifiedSince"])

        let extensionRealm = try makeExtensionRealm()
        try load(into: extensionRealm)

        let loadedAccount = try XCTUnwrap(TalkAccount.object(in: extensionRealm, forPrimaryKey: TestBaseRealm.fakeAccountId))
        XCTAssertEqual(loadedAccount.userDisplayName, "Display Name")
        XCTAssertEqual(loadedAccount.userPublicKey, "publicKey")
        XCTAssertEqual(loadedAccount.unreadBadgeNumber, 3)
        XCTAssertTrue(loadedAccount.active)
        XCTAssertEqual(loadedAccount.groupIds.count, 2)
        XCTAssertEqual(loadedAccount.groupIds.object(at: 1) as? String, "staff")

        let loadedRoom = try XCTUnwrap(NCRoom.object(in: extensionRealm, forPrimaryKey: "token@\(TestBaseRealm.fakeAccountId)"))
        XCTAssertEqual(loadedRoom.displayName, "Room")
        XCTAssertEqual(loadedRoom.lastActivity, 1234)
        XCTAssertTrue(loadedRoom.isFavorite)
        XCTAssertEqual(loadedRoom.unreadMessages, 0)

        let loadedCapabilities = try XCTUnwrap(ServerCapabilities.object(in: extensionRealm, forPrimaryKey: TestBaseRealm.fakeAccountId))
        XCTAssertEqual(loadedCapabilities.versionMajor, 32)
        XCTAssertEqual(loadedCapabilities.attachmentsFolder, "/Talk")
        XCTAssertEqual(loadedCapabilities.talkCapabilities.count, 2)
    }

    func testReloadRemovesDeletedObjects() throws {
        addRoom(withToken: "kept")
        let removedRoom = addRoom(withToken: "removed")

        let account = try XCTUnwrap(TalkAccount.object(forPrimaryKey: TestBaseRealm.fakeAccountId))
        try realm.transaction {
            account.userPublicKey = "publicKey"
        }

        let extensionRealm = try makeExtensionRealm()
        try load(into: extensionRealm)
        XCTAssertEqual(NCRoom.allObjects(in: extensionRealm).count, 2)

        try realm.transaction {
            realm.delete(removedRoom)
            account.userPublicKey = nil
        }

        try load(into: extensionRealm)
        XCTAssertEqual(NCRoom.allObjects(in: extensionRealm).count, 1)
        XCTAssertNotNil(NCRoom.object(in: extensionRealm, forPrimaryKey: "kept@\(TestBaseRealm.fakeAccountId)"))
        XCTAssertEqual(TalkAccount.allObjects(in: extensionRealm).count, 1)
        // A value cleared in the app is missing in the property list, but must be cleared in the extension as well
        XCTAssertNil(TalkAccount.object(in: extensionRealm, forPrimaryKey: TestBaseRealm.fakeAccountId)?.userPublicKey)
    }

    func testSnapshotOfDifferentSchemaIsRejected() throws {
        var snapshot = try snapshot(of: .accounts)
        snapshot["schemaVersion"] = NSNumber(value: kTalkDatabaseSchemaVersion - 1)

        let extensionRealm = try makeExtensionRealm()
        XCTAssertFalse(ExtensionDataStore.load(snapshot, of: .accounts, into: extensionRealm))
        XCTAssertEqual(TalkAccount.allObjects(in: extensionRealm).count, 0)
    }

    func testDefaultValuesCreateValidObjects() throws {
        // A missing or wrongly typed default makes loading throw an exception Swift can't catch, crashing every extension
        let extensionRealm = try makeExtensionRealm()

        for part in ExtensionDataStore.Part.allCases {
            for objectClass in part.objectClasses {
                let objectSchema = try XCTUnwrap(extensionRealm.schema.schema(forClassName: objectClass.className()))
                var value = ExtensionDataStore.defaultValues(for: objectSchema)
                let primaryKey = try XCTUnwrap(objectClass.primaryKey())
                value[primaryKey] = "id"

                try extensionRealm.transaction {
                    _ = objectClass.createOrUpdateModified(in: extensionRealm, withValue: value)
                }
            }
        }

        XCTAssertEqual(TalkAccount.allObjects(in: extensionRealm).count, 1)
        XCTAssertEqual(NCRoom.allObjects(in: extensionRealm).count, 1)
    }

    func testListedPropertiesExist() throws {
        // The lists are keyed by name, so a renamed property would silently drop out of them
        let listedProperties = ExtensionDataStore.excludedProperties.merging(ExtensionDataStore.passiveProperties) { $0.union($1) }

        for (className, names) in listedProperties {
            let objectSchema = try XCTUnwrap(realm.schema.schema(forClassName: className), className)
            let propertyNames = Set(objectSchema.properties.map(\.name))
            XCTAssertTrue(names.isSubset(of: propertyNames), "Unknown \(className) properties: \(names.subtracting(propertyNames))")
        }
    }

    func testFederatedCapabilitiesRoundTrip() throws {
        let capabilities = FederatedCapabilities()
        capabilities.internalId = "\(TestBaseRealm.fakeAccountId)@remote@token"
        capabilities.accountId = TestBaseRealm.fakeAccountId
        capabilities.remoteServer = "remote"
        capabilities.roomToken = "token"
        capabilities.chatMaxLength = 1000
        try realm.transaction {
            realm.add(capabilities)
        }

        let extensionRealm = try makeExtensionRealm()
        try load(into: extensionRealm)

        let loadedCapabilities = try XCTUnwrap(FederatedCapabilities.object(in: extensionRealm, forPrimaryKey: capabilities.internalId))
        XCTAssertEqual(loadedCapabilities.remoteServer, "remote")
        XCTAssertEqual(loadedCapabilities.chatMaxLength, 1000)
    }

    // MARK: - Files

    func testLoadSnapshotFromPublishedFiles() throws {
        addRoom(withToken: "token")
        publish()

        let extensionRealm = try makeExtensionRealm()
        XCTAssertTrue(ExtensionDataStore.loadSnapshot(into: extensionRealm))
        XCTAssertEqual(TalkAccount.allObjects(in: extensionRealm).count, 1)
        XCTAssertEqual(NCRoom.allObjects(in: extensionRealm).count, 1)
    }

    func testLoadSnapshotWithoutPublishedFilesFails() throws {
        let extensionRealm = try makeExtensionRealm()
        XCTAssertFalse(ExtensionDataStore.loadSnapshot(into: extensionRealm))
    }

    // MARK: - Events

    func testRecordedEventsAreCountedOnceBeforeAndAfterMerge() throws {
        publish()

        ExtensionDataStore.recordEvent(.unreadNotification, forAccountId: TestBaseRealm.fakeAccountId)
        ExtensionDataStore.recordEvent(.unreadNotification, forAccountId: TestBaseRealm.fakeAccountId)

        // Not merged yet, so the extension applies the pending events itself
        let extensionRealm = try makeExtensionRealm()
        XCTAssertTrue(ExtensionDataStore.loadSnapshot(into: extensionRealm))
        XCTAssertEqual(badgeNumber(in: extensionRealm), 2)

        merge()
        XCTAssertEqual(badgeNumber(in: realm), 2)
        XCTAssertTrue(ExtensionDataStore.pendingEvents().isEmpty)

        XCTAssertTrue(ExtensionDataStore.loadSnapshot(into: extensionRealm))
        XCTAssertEqual(badgeNumber(in: extensionRealm), 2)
        let newExtensionRealm = try makeExtensionRealm()
        XCTAssertTrue(ExtensionDataStore.loadSnapshot(into: newExtensionRealm))
        XCTAssertEqual(badgeNumber(in: newExtensionRealm), 2)
    }

    func testRoomsAreOnlyReloadedWhenPublishedAgain() throws {
        let room = addRoom(withToken: "token") { $0.displayName = "Room" }
        publish()

        let extensionRealm = try makeExtensionRealm()
        XCTAssertTrue(ExtensionDataStore.loadSnapshot(into: extensionRealm))
        let loadedRoom = try XCTUnwrap(NCRoom.object(in: extensionRealm, forPrimaryKey: room.internalId))

        // Only changed in the extension, so reloading the rooms would overwrite it
        try extensionRealm.transaction {
            loadedRoom.displayName = "Local"
        }

        XCTAssertTrue(ExtensionDataStore.loadSnapshot(into: extensionRealm))
        XCTAssertEqual(loadedRoom.displayName, "Local")

        try realm.transaction {
            room.displayName = "Renamed"
        }
        publish()

        XCTAssertTrue(ExtensionDataStore.loadSnapshot(into: extensionRealm))
        XCTAssertEqual(loadedRoom.displayName, "Renamed")
    }

    func testEventMergedButNotDeletedIsNotCountedTwice() throws {
        publish()
        ExtensionDataStore.recordEvent(.unreadNotification, forAccountId: TestBaseRealm.fakeAccountId)

        // Committed, but the file is not deleted yet
        let events = ExtensionDataStore.mergeEvents(into: realm)
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(ExtensionDataStore.mergeEvents(into: realm).isEmpty)

        // Published in between, like a change notification that comes before the merge finishes
        ExtensionDataStore.writeSnapshot(.accounts, from: realm)
        XCTAssertEqual(ExtensionDataStore.pendingEvents().count, 1)

        let extensionRealm = try makeExtensionRealm()
        XCTAssertTrue(ExtensionDataStore.loadSnapshot(into: extensionRealm))
        XCTAssertEqual(badgeNumber(in: extensionRealm), 1)

        ExtensionDataStore.finishMerge(of: events, from: realm)
        XCTAssertTrue(ExtensionDataStore.pendingEvents().isEmpty)

        XCTAssertTrue(ExtensionDataStore.loadSnapshot(into: extensionRealm))
        XCTAssertEqual(badgeNumber(in: extensionRealm), 1)
        XCTAssertEqual(badgeNumber(in: realm), 1)
    }

    func testEventsUpdateTheRightAccount() throws {
        try addInactiveAccount(withAccountId: "inactive")
        publish()

        ExtensionDataStore.recordEvent(.unreadNotification, forAccountId: TestBaseRealm.fakeAccountId)
        ExtensionDataStore.recordEvent(.unreadNotification, forAccountId: "inactive")
        ExtensionDataStore.recordEvent(.federationInvitation, forAccountId: "inactive")
        ExtensionDataStore.recordEvent(.unreadNotification, forAccountId: "unknown")
        merge()

        let activeAccount = try XCTUnwrap(TalkAccount.object(forPrimaryKey: TestBaseRealm.fakeAccountId))
        XCTAssertEqual(activeAccount.unreadBadgeNumber, 1)
        XCTAssertFalse(activeAccount.unreadNotification)
        XCTAssertEqual(activeAccount.pendingFederationInvitations, 0)

        let inactiveAccount = try XCTUnwrap(TalkAccount.object(forPrimaryKey: "inactive"))
        XCTAssertEqual(inactiveAccount.unreadBadgeNumber, 1)
        XCTAssertTrue(inactiveAccount.unreadNotification)
        XCTAssertEqual(inactiveAccount.pendingFederationInvitations, 1)

        XCTAssertNil(TalkAccount.object(forPrimaryKey: "unknown"))
        XCTAssertTrue(ExtensionDataStore.pendingEvents().isEmpty)
    }

    func testMalformedEventFileIsSkippedAndRemoved() throws {
        let eventsFolderURL = try XCTUnwrap(ExtensionDataStore.eventsFolderURL)
        let brokenURL = eventsFolderURL.appendingPathComponent("broken.plist")
        try FileManager.default.createDirectory(at: eventsFolderURL, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: brokenURL)

        ExtensionDataStore.recordEvent(.unreadNotification, forAccountId: TestBaseRealm.fakeAccountId)

        XCTAssertEqual(ExtensionDataStore.pendingEvents().count, 1)
        merge()
        XCTAssertEqual(badgeNumber(in: realm), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: brokenURL.path))
    }

    func testEventsKeepAccountIdsWithSpecialCharacters() throws {
        let accountId = "user name@https://cloud.example.com/sub/path?x=1+2"
        ExtensionDataStore.recordEvent(.federationInvitation, forAccountId: accountId)

        let events = ExtensionDataStore.pendingEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.accountId, accountId)
        XCTAssertEqual(events.first?.type, .federationInvitation)
    }

    func testDeletedEventsStayMarkedAppliedForAWhile() throws {
        publish()
        ExtensionDataStore.recordEvent(.unreadNotification, forAccountId: TestBaseRealm.fakeAccountId)
        let events = ExtensionDataStore.pendingEvents()
        merge()

        // An extension that listed the file right before it was deleted must not count it again from a later snapshot
        let snapshot = try publishedAccountsSnapshotAfterChange()
        let appliedEventIds = try XCTUnwrap(snapshot["appliedEventIds"] as? [String])
        // Other tests can leave ids of their own within the grace period
        XCTAssertTrue(Set(appliedEventIds).isSuperset(of: events.map(\.id)))

        let extensionRealm = try makeExtensionRealm()
        XCTAssertTrue(ExtensionDataStore.load(snapshot, of: .accounts, into: extensionRealm, pendingEvents: events))
        XCTAssertEqual(badgeNumber(in: extensionRealm), 1)
    }

    // Publishes the accounts again with a change, like a later change notification would
    private func publishedAccountsSnapshotAfterChange() throws -> [String: Any] {
        let account = try XCTUnwrap(TalkAccount.object(forPrimaryKey: TestBaseRealm.fakeAccountId))
        try realm.transaction {
            account.userDisplayName = "Changed"
        }
        ExtensionDataStore.writeSnapshot(.accounts, from: realm)

        let url = try XCTUnwrap(ExtensionDataStore.snapshotURL(for: .accounts))
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    func testDigestOnlyChangesWithContent() throws {
        addRoom(withToken: "token") { $0.displayName = "Room" }

        let first = ExtensionDataStore.makeSnapshot(of: .rooms, from: realm)
        let second = ExtensionDataStore.makeSnapshot(of: .rooms, from: realm)
        XCTAssertEqual(first.digest, second.digest)

        let room = try XCTUnwrap(NCRoom.object(forPrimaryKey: "token@\(TestBaseRealm.fakeAccountId)"))
        try realm.transaction {
            room.displayName = "Renamed"
        }

        XCTAssertNotEqual(ExtensionDataStore.makeSnapshot(of: .rooms, from: realm).digest, first.digest)
    }

    // MARK: - Triggers

    // Waits for the initial callback, so later calls are caused by the test's changes
    private func observe(_ objectClass: RLMObject.Type, keyPaths: [String], onChange: @escaping () -> Void) -> RLMNotificationToken {
        let initialCall = expectation(description: "Initial call")
        let token = objectClass.allObjects(in: realm).addNotificationBlock({ _, change, _ in
            if change == nil {
                initialCall.fulfill()
            } else {
                onChange()
            }
        }, keyPaths: keyPaths)

        wait(for: [initialCall], timeout: 5)
        return token
    }

    func testTriggerKeyPathsCanBeObserved() throws {
        // Registering throws for an invalid key path, which would crash the app at launch
        for part in ExtensionDataStore.Part.allCases {
            for objectClass in part.objectClasses {
                let keyPaths = ExtensionDataStore.triggerKeyPaths(for: objectClass, in: realm)
                XCTAssertFalse(keyPaths.isEmpty)
                observe(objectClass, keyPaths: keyPaths) {}.invalidate()
            }
        }
    }

    func testPassiveRoomChangesDontTrigger() throws {
        let room = addRoom(withToken: "token")

        var changeExpectation: XCTestExpectation?
        let token = observe(NCRoom.self, keyPaths: ExtensionDataStore.triggerKeyPaths(for: NCRoom.self, in: realm)) {
            changeExpectation?.fulfill()
        }
        defer { token.invalidate() }

        let noCall = expectation(description: "No call for passive or excluded properties")
        noCall.isInverted = true
        changeExpectation = noCall
        try realm.transaction {
            room.lastActivity = 1000
            room.unreadMessages = 3
            room.lastUpdate = 5
        }
        wait(for: [noCall], timeout: 1)

        let call = expectation(description: "Call for a published property")
        changeExpectation = call
        try realm.transaction {
            room.displayName = "Renamed"
        }
        wait(for: [call], timeout: 5)
    }

    func testRoomUpdateOnlyAssignsChangedValues() throws {
        let room = addRoom(withToken: "token") { $0.displayName = "Room" }

        var changeExpectation: XCTestExpectation?
        let token = observe(NCRoom.self, keyPaths: ExtensionDataStore.triggerKeyPaths(for: NCRoom.self, in: realm)) {
            changeExpectation?.fulfill()
        }
        defer { token.invalidate() }

        // Realm reports every assigned property as changed, so an update with equal values must not assign any
        let noCall = expectation(description: "No call for an update with equal values")
        noCall.isInverted = true
        changeExpectation = noCall
        try realm.transaction {
            NCRoom.update(room, with: NCRoom(value: room))
        }
        wait(for: [noCall], timeout: 1)

        let renamedRoom = NCRoom(value: room)
        renamedRoom.displayName = "Renamed"

        let call = expectation(description: "Call for an update with a changed value")
        changeExpectation = call
        try realm.transaction {
            NCRoom.update(room, with: renamedRoom)
        }
        wait(for: [call], timeout: 5)
        XCTAssertEqual(room.displayName, "Renamed")
    }
}
