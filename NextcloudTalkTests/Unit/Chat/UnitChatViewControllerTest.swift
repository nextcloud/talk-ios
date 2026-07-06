//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitChatViewControllerTest: TestBaseRealm {

    func testExpireMessages() throws {
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

        let chatViewController = ChatViewController(forRoom: room, withAccount: activeAccount)!
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

    func testJoinRoomWithEmptyRoomObject() throws {
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

        expectation(forNotification: .NCRoomsManagerDidJoinRoom, object: nil) { notification -> Bool in
            XCTAssertNil(notification.userInfo?["error"])

            XCTAssertEqual(notification.userInfo?["token"] as! String, roomToken)

            return true
        }

        let userInfo: [String: Any] = [
            "token": roomToken,
            "room": NCRoom()
        ]

        NotificationCenter.default.post(name: .NCRoomsManagerDidJoinRoom, object: self, userInfo: userInfo)

        waitForExpectations(timeout: TestConstants.timeoutShort, handler: nil)

        let exp = expectation(description: "\(#function)\(#line)")

        DispatchQueue.main.async {
            XCTAssertNotNil(chatViewController.room.token)
            exp.fulfill()
        }

        waitForExpectations(timeout: TestConstants.timeoutShort, handler: nil)
    }

    func testFrequentlyEmojis() throws {
        var activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        XCTAssertEqual(activeAccount.frequentlyUsedEmojis, ["👍", "❤️", "😂", "😅"])

        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "👍", forAccount: activeAccount.accountId)
        activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        XCTAssertEqual(activeAccount.frequentlyUsedEmojis, ["👍", "❤️", "😂", "😅"])

        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🙈", forAccount: activeAccount.accountId)
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
        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🇫🇮", forAccount: activeAccount.accountId)
        activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        XCTAssertEqual(activeAccount.frequentlyUsedEmojis, ["🇫🇮", "🙈", "👍", "❤️"])

        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "😵‍💫", forAccount: activeAccount.accountId)
        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "😵‍💫", forAccount: activeAccount.accountId)
        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "😵‍💫", forAccount: activeAccount.accountId)
        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🤷‍♂️", forAccount: activeAccount.accountId)
        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: "🤷‍♂️", forAccount: activeAccount.accountId)
        activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        XCTAssertEqual(activeAccount.frequentlyUsedEmojis, ["🇫🇮", "🙈", "😵‍💫", "🤷‍♂️"])
    }

    func testStoppedControllerDoesNotResumePollingOnChatRelayCatchUp() throws {
        let room = addRoom(withToken: "relayLeakRoom")
        let chatController = NCChatController(for: room)!

        // The user leaves the chat -> ChatViewController.leaveChat() -> stop()
        chatController.stop()
        XCTAssertTrue(chatController.isReceivingMessagesStoppedForTesting)

        // A chat-relay catch-up arriving around the time the chat is left must NOT
        // bring the stopped controller back to life and resume polling — otherwise
        // the in-flight poll task retains the controller, deinit never runs, and it
        // keeps pulling messages for a conversation the user already left.
        chatController.triggerChatRelayCatchUpForTesting()

        // triggerChatRelayCatchUp() schedules startReceivingChatMessages on the main
        // queue; let that run before asserting.
        let exp = expectation(description: "\(#function)\(#line)")
        DispatchQueue.main.async { exp.fulfill() }
        waitForExpectations(timeout: TestConstants.timeoutShort, handler: nil)

        XCTAssertTrue(chatController.isReceivingMessagesStoppedForTesting,
                      "A stopped NCChatController must not resume message polling after a chat-relay catch-up")
    }

    func testChatRelayCatchUpScheduledBeforeStopDoesNotResumePolling() throws {
        let room = addRoom(withToken: "relayLeakRoom2")
        let chatController = NCChatController(for: room)!

        // Reproduces the ordering the earlier fix missed: the catch-up is triggered while the user
        // is still in the room (relay active, not stopped), so it passes its guard and schedules the
        // restart on the main queue. Only *afterwards* does the user leave.
        chatController.markChatRelayActiveForTesting()
        chatController.triggerChatRelayCatchUpForTesting()

        // The user leaves now, after the restart is already queued on the main queue but before it runs.
        chatController.stop()
        XCTAssertTrue(chatController.isReceivingMessagesStoppedForTesting)

        // Drain the main queue so the queued startReceivingChatMessages runs. If it re-armed polling
        // (the old behaviour), it would clear the stop flag here.
        let exp = expectation(description: "\(#function)\(#line)")
        DispatchQueue.main.async { exp.fulfill() }
        waitForExpectations(timeout: TestConstants.timeoutShort, handler: nil)

        XCTAssertTrue(chatController.isReceivingMessagesStoppedForTesting,
                      "A chat-relay catch-up scheduled before stop() must not resume polling once stop() has run")
    }

    func testContentInsetAdjustsForOverlayViews() throws {
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
        XCTAssertEqual(chatViewController.tableView?.contentInset.top, 0)

        // Add a ChatOverlayView simulating a pinned message
        let overlayView = ChatOverlayView()
        overlayView.alpha = 1.0
        overlayView.frame = CGRect(x: 0, y: 0, width: 320, height: 80)
        chatViewController.view.addSubview(overlayView)

        chatViewController.viewDidLayoutSubviews()
        XCTAssertEqual(chatViewController.tableView?.contentInset.top, 80)

        // Add a taller ChatInfoView simulating a retention banner
        let infoView = ChatInfoView()
        infoView.alpha = 1.0
        infoView.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        chatViewController.view.addSubview(infoView)

        // Should use the tallest overlay
        chatViewController.viewDidLayoutSubviews()
        XCTAssertEqual(chatViewController.tableView?.contentInset.top, 120)

        // Remove the taller view -> should fall back to the shorter overlay
        infoView.removeFromSuperview()
        chatViewController.viewDidLayoutSubviews()
        XCTAssertEqual(chatViewController.tableView?.contentInset.top, 80)

        // Hide the remaining overlay via alpha (same as the fade-out animation)
        overlayView.alpha = 0
        chatViewController.viewDidLayoutSubviews()
        XCTAssertEqual(chatViewController.tableView?.contentInset.top, 0)

        // Remove it fully and confirm inset stays at 0
        overlayView.removeFromSuperview()
        chatViewController.viewDidLayoutSubviews()
        XCTAssertEqual(chatViewController.tableView?.contentInset.top, 0)
    }
}
