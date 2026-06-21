//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Testing
@testable import NextcloudTalk

@Suite(.serialized)
final class UnitChatViewControllerTest: TestBaseRealm {

    @Test func `expire messages`() async throws {
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

        #expect(NCChatMessage.allObjects().count == 2)

        let chatViewController = ChatViewController(forRoom: room, withAccount: activeAccount)!
        let messageArray = [expMessage1, expMessage2].map { NCChatMessage(value: $0) }

        chatViewController.appendMessages(messages: messageArray)
        chatViewController.removeExpiredMessages()

        // Since removeExpiredMessages is dispatched, we need to wait until it was scheduled
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }

        #expect(NCChatMessage.allObjects().firstObject() == nil)
    }

    @Test func `join room with empty room object`() async throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomName = "EmptyRoomObject"
        let roomToken = "emptyRoomObject"

        let room = NCRoom()
        room.token = roomToken
        room.name = roomName
        room.accountId = activeAccount.accountId

        try? realm.transaction {
            realm.add(room)
        }

        let chatViewController = ChatViewController(forRoom: room, withAccount: activeAccount)!

        let joinTracker = EventTracker()
        let observer = NotificationCenter.default.addObserver(forName: .NCRoomsManagerDidJoinRoom, object: nil, queue: nil) { notification in
            #expect(notification.userInfo?["error"] == nil)
            #expect(notification.userInfo?["token"] as? String == roomToken)
            joinTracker.signal()
        }

        let userInfo: [String: Any] = [
            "token": roomToken,
            "room": NCRoom()
        ]

        NotificationCenter.default.post(name: .NCRoomsManagerDidJoinRoom, object: self, userInfo: userInfo)
        NotificationCenter.default.removeObserver(observer)

        #expect(joinTracker.fired)

        // The room is processed asynchronously on the main queue
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }

        #expect(chatViewController.room.token != nil)
    }

    @Test func `frequently used emojis`() throws {
        var activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        #expect(activeAccount.frequentlyUsedEmojis == ["👍", "❤️", "😂", "😅"])

        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "👍", forAccount: activeAccount.accountId)
        activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        #expect(activeAccount.frequentlyUsedEmojis == ["👍", "❤️", "😂", "😅"])

        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🙈", forAccount: activeAccount.accountId)
        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🙈", forAccount: activeAccount.accountId)
        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🙈", forAccount: activeAccount.accountId)
        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🙈", forAccount: activeAccount.accountId)
        activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        #expect(activeAccount.frequentlyUsedEmojis == ["🙈", "👍", "❤️", "😂"])

        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🇫🇮", forAccount: activeAccount.accountId)
        activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        #expect(activeAccount.frequentlyUsedEmojis == ["🙈", "🇫🇮", "👍", "❤️"])

        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🇫🇮", forAccount: activeAccount.accountId)
        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🇫🇮", forAccount: activeAccount.accountId)
        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🇫🇮", forAccount: activeAccount.accountId)
        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🇫🇮", forAccount: activeAccount.accountId)
        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🇫🇮", forAccount: activeAccount.accountId)
        activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        #expect(activeAccount.frequentlyUsedEmojis == ["🇫🇮", "🙈", "👍", "❤️"])

        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "😵‍💫", forAccount: activeAccount.accountId)
        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "😵‍💫", forAccount: activeAccount.accountId)
        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "😵‍💫", forAccount: activeAccount.accountId)
        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🤷‍♂️", forAccount: activeAccount.accountId)
        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🤷‍♂️", forAccount: activeAccount.accountId)
        activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        #expect(activeAccount.frequentlyUsedEmojis == ["🇫🇮", "🙈", "😵‍💫", "🤷‍♂️"])
    }

    @Test func `content inset adjusts for overlay views`() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = NCRoom()
        room.token = "overlayToken"
        room.name = "Overlay Views Test Room"
        room.accountId = activeAccount.accountId

        try? realm.transaction {
            realm.add(room)
        }

        let chatViewController = ChatViewController(forRoom: room, withAccount: activeAccount)!

        // Load the view hierarchy so tableView and viewDidLayoutSubviews work
        chatViewController.loadViewIfNeeded()

        // Initially no overlay -> inset should be 0
        chatViewController.viewDidLayoutSubviews()
        #expect(chatViewController.tableView?.contentInset.top == 0)

        // Add a ChatOverlayView simulating a pinned message
        let overlayView = ChatOverlayView()
        overlayView.alpha = 1.0
        overlayView.frame = CGRect(x: 0, y: 0, width: 320, height: 80)
        chatViewController.view.addSubview(overlayView)

        chatViewController.viewDidLayoutSubviews()
        #expect(chatViewController.tableView?.contentInset.top == 80)

        // Add a taller ChatInfoView simulating a retention banner
        let infoView = ChatInfoView()
        infoView.alpha = 1.0
        infoView.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        chatViewController.view.addSubview(infoView)

        // Should use the tallest overlay
        chatViewController.viewDidLayoutSubviews()
        #expect(chatViewController.tableView?.contentInset.top == 120)

        // Remove the taller view -> should fall back to the shorter overlay
        infoView.removeFromSuperview()
        chatViewController.viewDidLayoutSubviews()
        #expect(chatViewController.tableView?.contentInset.top == 80)

        // Hide the remaining overlay via alpha (same as the fade-out animation)
        overlayView.alpha = 0
        chatViewController.viewDidLayoutSubviews()
        #expect(chatViewController.tableView?.contentInset.top == 0)

        // Remove it fully and confirm inset stays at 0
        overlayView.removeFromSuperview()
        chatViewController.viewDidLayoutSubviews()
        #expect(chatViewController.tableView?.contentInset.top == 0)
    }
}
