//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitConversationsWidgetTest: TestBaseRealm {

    private var account: TalkAccount {
        NCDatabaseManager.sharedInstance().activeAccount()
    }

    private func createRoom(withToken token: String, unreadMessages: Int = 0, isArchived: Bool = false) -> NCRoom {
        let room = NCRoom()
        room.accountId = account.accountId
        room.token = token
        room.displayName = "Room \(token)"
        room.type = .group
        room.unreadMessages = unreadMessages
        room.isArchived = isArchived

        return room
    }

    private func createSnapshot(withAccountIds accountIds: [String], activeAccountId: String?) -> ConversationsSnapshot {
        let accounts = accountIds.map { ConversationsSnapshot.Account(id: $0, displayName: $0, unreadConversationCount: 0, conversations: []) }

        return ConversationsSnapshot(appName: "Talk", themeColor: .init(red: 0, green: 0.5, blue: 1), activeAccountId: activeAccountId, accounts: accounts)
    }

    func testSnapshotConversation() throws {
        let room = createRoom(withToken: "abc123", unreadMessages: 3)
        room.unreadMention = true
        room.hasCall = true
        room.lastActivity = 1_700_000_000

        let conversation = ConversationsWidgetController.snapshotConversation(for: room, account: account)

        XCTAssertEqual(conversation.id, "abc123")
        XCTAssertEqual(conversation.displayName, "Room abc123")
        XCTAssertEqual(conversation.unreadMessages, 3)
        XCTAssertTrue(conversation.hasUnreadMention)
        XCTAssertTrue(conversation.hasCall)
        XCTAssertEqual(conversation.lastActivity, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertNil(conversation.lastMessage)
        XCTAssertEqual(conversation.avatarFileName, ConversationsSnapshot.avatarFileName(forAccountId: account.accountId, roomToken: "abc123"))

        let url = try XCTUnwrap(conversation.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "nextcloudtalk")
        XCTAssertEqual(components.host, "open-conversation")
        XCTAssertEqual(components.queryItems?.first { $0.name == "server" }?.value, account.server)
        XCTAssertEqual(components.queryItems?.first { $0.name == "user" }?.value, account.userId)
        XCTAssertEqual(components.queryItems?.first { $0.name == "withRoomToken" }?.value, "abc123")
    }

    func testLastMessageIsHiddenForSensitiveConversations() throws {
        let message = NCChatMessage()
        message.internalId = "internal1"
        message.accountId = account.accountId
        message.token = "abc123"
        message.actorId = "alice"
        message.actorType = "users"
        message.actorDisplayName = "Alice"
        message.message = "The new mockups are ready"
        message.timestamp = Int(Date().timeIntervalSince1970)

        try realm.transaction {
            realm.add(message)
        }

        let room = createRoom(withToken: "abc123")
        room.lastMessageId = "internal1"

        let lastMessage = try XCTUnwrap(ConversationsWidgetController.snapshotConversation(for: room, account: account).lastMessage)
        XCTAssertTrue(lastMessage.contains("The new mockups are ready"))

        room.isSensitive = true
        XCTAssertNil(ConversationsWidgetController.snapshotConversation(for: room, account: account).lastMessage)
    }

    func testSnapshotAccount() {
        var rooms = (1...10).map { createRoom(withToken: "room\($0)", unreadMessages: $0 % 2) }
        rooms.insert(createRoom(withToken: "archived", unreadMessages: 5, isArchived: true), at: 0)

        let snapshotAccount = ConversationsWidgetController.snapshotAccount(for: account, rooms: rooms)

        XCTAssertEqual(snapshotAccount.id, account.accountId)
        XCTAssertEqual(snapshotAccount.conversations.count, ConversationsSnapshot.maxConversationsPerAccount)
        XCTAssertEqual(snapshotAccount.conversations.first?.id, "room1")
        XCTAssertFalse(snapshotAccount.conversations.contains { $0.id == "archived" })
        // Rooms 1, 3, 5, 7 and 9 are unread, including the ones that are not shown
        XCTAssertEqual(snapshotAccount.unreadConversationCount, 5)
    }

    func testSnapshotAccountSelection() {
        let snapshot = createSnapshot(withAccountIds: ["a", "b", "c"], activeAccountId: "b")

        XCTAssertEqual(snapshot.account(withId: "c")?.id, "c")
        XCTAssertEqual(snapshot.account(withId: nil)?.id, "b")
        XCTAssertEqual(snapshot.account(withId: "removed")?.id, "b")

        let snapshotWithoutActiveAccount = createSnapshot(withAccountIds: ["a", "b"], activeAccountId: nil)
        XCTAssertEqual(snapshotWithoutActiveAccount.account(withId: nil)?.id, "a")

        XCTAssertNil(createSnapshot(withAccountIds: [], activeAccountId: nil).account(withId: nil))
    }

    func testSnapshotIsOnlyWrittenWhenChanged() throws {
        let containerURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: containerURL) }

        XCTAssertNil(ConversationsSnapshot.load(from: containerURL))

        var snapshot = createSnapshot(withAccountIds: ["a"], activeAccountId: "a")
        XCTAssertTrue(try snapshot.write(to: containerURL))
        XCTAssertFalse(try snapshot.write(to: containerURL))
        XCTAssertEqual(ConversationsSnapshot.load(from: containerURL), snapshot)

        snapshot.accounts[0].unreadConversationCount = 2
        XCTAssertTrue(try snapshot.write(to: containerURL))
        XCTAssertEqual(ConversationsSnapshot.load(from: containerURL), snapshot)
    }

    func testAvatarFileName() {
        let fileName = ConversationsSnapshot.avatarFileName(forAccountId: "alice@https://cloud.example.com/", roomToken: "abc123")

        XCTAssertTrue(fileName.hasSuffix(".png"))
        XCTAssertFalse(fileName.contains("/"))
        XCTAssertNotEqual(fileName, ConversationsSnapshot.avatarFileName(forAccountId: "bob@https://cloud.example.com/", roomToken: "abc123"))
    }

    func testFormattedDate() throws {
        let calendar = Calendar.current
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 12)))

        let today = try XCTUnwrap(calendar.date(byAdding: .hour, value: -3, to: now))
        XCTAssertEqual(ConversationsSnapshot.formattedDate(today, now: now), today.formatted(date: .omitted, time: .shortened))

        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        XCTAssertEqual(ConversationsSnapshot.formattedDate(yesterday, now: now), NSLocalizedString("Yesterday", comment: ""))

        let lastWeek = try XCTUnwrap(calendar.date(byAdding: .day, value: -4, to: now))
        XCTAssertEqual(ConversationsSnapshot.formattedDate(lastWeek, now: now), lastWeek.formatted(.dateTime.weekday(.abbreviated)))

        let lastMonth = try XCTUnwrap(calendar.date(byAdding: .day, value: -30, to: now))
        XCTAssertEqual(ConversationsSnapshot.formattedDate(lastMonth, now: now), lastMonth.formatted(.dateTime.day().month(.abbreviated)))
    }
}
