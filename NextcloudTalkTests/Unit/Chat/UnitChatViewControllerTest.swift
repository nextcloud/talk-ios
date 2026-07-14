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

    // MARK: - Batch update computation when receiving messages

    private func makeMessage(id: Int, timestamp: Int, actorId: String = "alice",
                             inRoom room: NCRoom, withAccount account: TalkAccount) -> NCChatMessage {
        let message = NCChatMessage()
        message.internalId = "internal-\(id)"
        message.messageId = id
        message.accountId = account.accountId
        message.actorId = actorId
        message.actorType = "users"
        message.timestamp = timestamp
        message.token = room.token
        message.message = "Message \(id)"
        return message
    }

    // Pins the working behavior: a message for a not-yet-known, newer day
    // creates a section that sorts to the end and is registered as an insert.
    func testReceivedMessageForNewerDayInsertsSectionAtTheEnd() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = addRoom(withToken: "batchNewDay")
        let chatViewController = try XCTUnwrap(ChatViewController(forRoom: room, withAccount: activeAccount))
        chatViewController.loadViewIfNeeded()
        let tableView = try XCTUnwrap(chatViewController.tableView)

        let now = Int(Date().timeIntervalSince1970)

        // Existing state: one section from yesterday, table view in sync
        chatViewController.appendMessages(messages: [makeMessage(id: 1, timestamp: now - 86400, inRoom: room, withAccount: activeAccount)])
        tableView.reloadData()
        XCTAssertEqual(tableView.numberOfSections, 1)

        let update = chatViewController.appendReceivedMessagesAndComputeTableViewUpdate(
            for: [makeMessage(id: 2, timestamp: now, inRoom: room, withAccount: activeAccount)], in: tableView)

        XCTAssertEqual(chatViewController.dateSections.count, 2)
        XCTAssertEqual(update.insertSections, IndexSet(integer: 1))
        XCTAssertEqual(update.insertIndexPaths, [IndexPath(row: 0, section: 1)])
        XCTAssertTrue(update.reloadIndexPaths.isEmpty)
    }

    // Pins the working behavior: a message for an already existing day is a plain row insert.
    func testReceivedMessageForExistingDayInsertsRow() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = addRoom(withToken: "batchSameDay")
        let chatViewController = try XCTUnwrap(ChatViewController(forRoom: room, withAccount: activeAccount))
        chatViewController.loadViewIfNeeded()
        let tableView = try XCTUnwrap(chatViewController.tableView)

        let now = Int(Date().timeIntervalSince1970)

        chatViewController.appendMessages(messages: [makeMessage(id: 1, timestamp: now - 60, inRoom: room, withAccount: activeAccount)])
        tableView.reloadData()
        XCTAssertEqual(tableView.numberOfSections, 1)

        let update = chatViewController.appendReceivedMessagesAndComputeTableViewUpdate(
            for: [makeMessage(id: 2, timestamp: now, actorId: "bob", inRoom: room, withAccount: activeAccount)], in: tableView)

        XCTAssertTrue(update.insertSections.isEmpty)
        XCTAssertEqual(update.insertIndexPaths, [IndexPath(row: 1, section: 0)])
        XCTAssertTrue(update.reloadIndexPaths.isEmpty)
    }

    // Reproduces the crash condition behind
    // _Bug_Detected_In_Client_Of_UITableView_Invalid_Batch_Updates:
    // a backlog message from an older day (no section yet) creates a section that
    // sorts *before* the existing one. It must be part of insertSections, otherwise
    // the data source reports one section more than "before + inserted" and the
    // batch update raises NSInternalInconsistencyException.
    func testReceivedMessageForOlderDayMustInsertTheNewSection() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = addRoom(withToken: "batchOlderDay")
        let chatViewController = try XCTUnwrap(ChatViewController(forRoom: room, withAccount: activeAccount))
        chatViewController.loadViewIfNeeded()
        let tableView = try XCTUnwrap(chatViewController.tableView)

        let now = Int(Date().timeIntervalSince1970)

        // Existing state: the user just sent a message, so only *today's* section exists
        chatViewController.appendMessages(messages: [makeMessage(id: 100, timestamp: now, inRoom: room, withAccount: activeAccount)])
        tableView.reloadData()
        XCTAssertEqual(tableView.numberOfSections, 1)

        // A message from yesterday arrives (e.g. missed messages fetched after reconnecting)
        let update = chatViewController.appendReceivedMessagesAndComputeTableViewUpdate(
            for: [makeMessage(id: 99, timestamp: now - 86400, actorId: "bob", inRoom: room, withAccount: activeAccount)], in: tableView)

        XCTAssertEqual(chatViewController.dateSections.count, 2)

        // UIKit validates: sections after (2) == sections before (1) + inserted - deleted
        XCTAssertEqual(update.insertSections, IndexSet(integer: 0),
                       "The section for the older day must be inserted even though it does not sort to the end")

        // The bug classifies the message as a reload of (0, 0) - the wrong section
        XCTAssertTrue(update.reloadIndexPaths.isEmpty,
                      "Nothing changed in the pre-existing section, so nothing may be reloaded")
    }

    // When an older-day section is inserted, existing sections shift. Inserts must use
    // post-update indices, while reloads of already known rows must keep pre-update indices.
    func testReloadUsesPreUpdateCoordinatesWhenOlderDaySectionIsInserted() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = addRoom(withToken: "batchShiftedReload")
        let chatViewController = try XCTUnwrap(ChatViewController(forRoom: room, withAccount: activeAccount))
        chatViewController.loadViewIfNeeded()
        let tableView = try XCTUnwrap(chatViewController.tableView)

        let now = Int(Date().timeIntervalSince1970)

        // Existing state: one message in today's section, table view in sync
        chatViewController.appendMessages(messages: [makeMessage(id: 100, timestamp: now, inRoom: room, withAccount: activeAccount)])
        tableView.reloadData()
        XCTAssertEqual(tableView.numberOfSections, 1)

        // One backlog message from yesterday plus an echo of the already known message
        let update = chatViewController.appendReceivedMessagesAndComputeTableViewUpdate(
            for: [makeMessage(id: 99, timestamp: now - 86400, actorId: "bob", inRoom: room, withAccount: activeAccount),
                  makeMessage(id: 100, timestamp: now, inRoom: room, withAccount: activeAccount)], in: tableView)

        // Yesterday's section is inserted at its sorted position (post-update coordinates)
        XCTAssertEqual(update.insertSections, IndexSet(integer: 0))
        XCTAssertEqual(update.insertIndexPaths, [IndexPath(row: 0, section: 0)])

        // The echo reloads the known message in the section the tableView still knows as 0,
        // even though it is section 1 in the updated data source
        XCTAssertEqual(update.reloadIndexPaths, [IndexPath(row: 0, section: 0)])
    }
}
