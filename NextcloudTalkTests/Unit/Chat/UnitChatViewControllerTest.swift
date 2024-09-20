//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitChatViewControllerTest: TestBaseRealm {

    func testLocalMention() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomName = "Expire Messages Test Room"
        let roomToken = "expToken"

        let room = NCRoom()
        room.token = roomToken
        room.name = roomName
        room.accountId = activeAccount.accountId

        // Create 2 messages which are in different sections
        let expMessage1 = NCChatMessage()

        expMessage1.internalId = "internal1"
        expMessage1.accountId = activeAccount.accountId
        expMessage1.actorDisplayName = activeAccount.userDisplayName
        expMessage1.actorId = activeAccount.userId
        expMessage1.actorType = "users"
        expMessage1.timestamp = Int(Date().timeIntervalSince1970) - 1000000
        expMessage1.expirationTimestamp = Int(Date().timeIntervalSince1970) - 1000
        expMessage1.token = roomToken
        expMessage1.message = "Message 1"

        let expMessage2 = NCChatMessage()

        expMessage2.internalId = "internal2"
        expMessage2.accountId = activeAccount.accountId
        expMessage2.actorDisplayName = activeAccount.userDisplayName
        expMessage2.actorId = activeAccount.userId
        expMessage2.actorType = "users"
        expMessage2.timestamp = Int(Date().timeIntervalSince1970)
        expMessage2.expirationTimestamp = Int(Date().timeIntervalSince1970) - 1000
        expMessage2.token = roomToken
        expMessage2.message = "Message 2"

        try? realm.transaction {
            realm.add(room)
            realm.add(expMessage1)
            realm.add(expMessage2)
        }

        XCTAssertEqual(NCChatMessage.allObjects().count, 2)

        let chatViewController = ChatViewController(for: room)!
        let messageArray = [expMessage1, expMessage2].map { NCChatMessage(value: $0) }

        chatViewController.appendMessages(messages: messageArray)
        chatViewController.removeExpiredMessages()

        // Since removeExpiredMessages is dispatched, we need to wait until it was scheduled
        let exp = expectation(description: "\(#function)\(#line)")

        DispatchQueue.main.async {
            exp.fulfill()
        }

        waitForExpectations(timeout: TestConstants.timeoutShort, handler: nil)

        XCTAssertEqual(NCChatMessage.allObjects().count, 0)
    }

    func testFrequentlyEmojis() throws {
        var activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        XCTAssertEqual(activeAccount.frequentlyUsedEmojis, ["👍", "❤️", "😂", "😅"])

        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🙈", forAccount: activeAccount.accountId)
        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🙈", forAccount: activeAccount.accountId)
        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🙈", forAccount: activeAccount.accountId)
        activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        XCTAssertEqual(activeAccount.frequentlyUsedEmojis, ["🙈", "👍", "❤️", "😂"])

        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🇫🇮", forAccount: activeAccount.accountId)
        activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        XCTAssertEqual(activeAccount.frequentlyUsedEmojis, ["🙈", "🇫🇮", "👍", "❤️"])

        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🇫🇮", forAccount: activeAccount.accountId)
        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🇫🇮", forAccount: activeAccount.accountId)
        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🇫🇮", forAccount: activeAccount.accountId)
        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🇫🇮", forAccount: activeAccount.accountId)
        activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        XCTAssertEqual(activeAccount.frequentlyUsedEmojis, ["🇫🇮", "🙈", "👍", "❤️"])

        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "😵‍💫", forAccount: activeAccount.accountId)
        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "😵‍💫", forAccount: activeAccount.accountId)
        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🤷‍♂️", forAccount: activeAccount.accountId)
        activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        XCTAssertEqual(activeAccount.frequentlyUsedEmojis, ["🇫🇮", "🙈", "😵‍💫", "🤷‍♂️"])
    }
}
