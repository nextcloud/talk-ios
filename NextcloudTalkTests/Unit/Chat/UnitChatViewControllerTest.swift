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

    // MARK: - Chat relay

    // A signaling controller that advertises the chat relay but never connects: without a websocket
    // the callbacks of the failing connection attempt are ignored, so nothing reconnects underneath
    // the assertions.
    private func inertSignalingController() -> NCExternalSignalingController {
        let account = NCDatabaseManager.sharedInstance().activeAccount()
        let signalingController = NCExternalSignalingController(account: account, serverUrl: TestConstants.server, ticket: "fakeTicket")

        signalingController.disconnect()
        signalingController.helloResponseReceived(messageDict: [
            "type": "hello",
            "id": "1",
            "hello": [
                "sessionid": "session-1",
                "server": ["version": "2.0.0", "features": ["chat-relay"]]
            ]
        ])

        return signalingController
    }

    private func drainMainQueue() {
        let exp = expectation(description: "\(#function)\(#line)")
        DispatchQueue.main.async { exp.fulfill() }
        waitForExpectations(timeout: TestConstants.timeoutShort, handler: nil)
    }

    func testUpToDateChatKeepsPollingUntilTheRoomIsJoinedOnTheSignalingServer() throws {
        let room = addRoom(withToken: "relayJoinRoom")
        let chatController = NCChatController(for: room)!
        let signalingController = inertSignalingController()

        chatController.setupChatRelayForTesting(with: signalingController)

        // The chat is up to date, but our session is not in the room yet, so the relay would not
        // deliver anything to us: keep long polling instead of handing over.
        chatController.handOverPollingToChatRelayForTesting()
        chatController.waitForChatRelayQueueForTesting()
        XCTAssertEqual(chatController.chatRelayStateForTesting, .inactive)
        XCTAssertFalse(chatController.isReceivingMessagesStoppedForTesting)

        // Being in *another* room is not enough either
        signalingController.roomMessageReceived(messageDict: ["type": "room", "room": ["roomid": "someOtherRoom"]])
        chatController.handOverPollingToChatRelayForTesting()
        chatController.waitForChatRelayQueueForTesting()
        XCTAssertEqual(chatController.chatRelayStateForTesting, .inactive)

        // Our room was acked, so the first long poll reporting an up-to-date chat after that hands over
        signalingController.roomMessageReceived(messageDict: ["type": "room", "room": ["roomid": room.token]])
        chatController.handOverPollingToChatRelayForTesting()
        chatController.waitForChatRelayQueueForTesting()
        XCTAssertEqual(chatController.chatRelayStateForTesting, .active)

        chatController.stop()
        drainMainQueue()
    }

    func testCatchUpDoesNotHandOverToTheRelayWhileTheRoomIsNotJoined() throws {
        let room = addRoom(withToken: "relayCatchUpRoom")
        let chatController = NCChatController(for: room)!
        let signalingController = inertSignalingController()

        chatController.setupChatRelayForTesting(with: signalingController)

        // The relay is active and a catch-up is running when the session is replaced by a reconnect
        // that could not resume. The catch-up must not re-arm the relay: the new session did not
        // re-join the room yet.
        signalingController.roomMessageReceived(messageDict: ["type": "room", "room": ["roomid": room.token]])
        chatController.markChatRelayActiveForTesting()
        signalingController.resetWebSocket()

        chatController.handOverPollingToChatRelayForTesting()
        chatController.waitForChatRelayQueueForTesting()
        XCTAssertEqual(chatController.chatRelayStateForTesting, .inactive)

        chatController.stop()
        drainMainQueue()
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
        message.actorDisplayName = "DisplayName \(actorId)"
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

    // A received message written by the user (e.g. sent from another device) removes the
    // unread messages separator. The removal runs right before the batch update that inserts
    // the received messages, so the insert coordinates must account for the deleted row.
    func testReceivedOwnMessageRemovesUnreadSeparator() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = addRoom(withToken: "batchSeparatorRemoval")
        let chatViewController = try XCTUnwrap(ChatViewController(forRoom: room, withAccount: activeAccount))
        chatViewController.loadViewIfNeeded()
        let tableView = try XCTUnwrap(chatViewController.tableView)

        let now = Int(Date().timeIntervalSince1970)

        // Existing state: a message from another user with the unread messages separator below it
        chatViewController.appendMessages(messages: [makeMessage(id: 1, timestamp: now - 60, actorId: "bob", inRoom: room, withAccount: activeAccount)])

        let separator = NCChatMessage()
        separator.messageId = MessageSeparatorTableViewCell.unreadMessagesSeparatorId
        let lastDateSection = try XCTUnwrap(chatViewController.dateSections.last)
        chatViewController.messages[lastDateSection]?.append(separator)

        // Force a layout pass so the reload is actually performed: the view is not part of a
        // window here, so the table would otherwise lazily reload against the data source only
        // when the batch update runs - at that point it was already mutated, so the update's
        // pre-update coordinates would not match and performBatchUpdates would raise
        tableView.reloadData()
        tableView.layoutIfNeeded()
        XCTAssertEqual(tableView.numberOfRows(inSection: 0), 2)
        XCTAssertNotNil(chatViewController.indexPathForUnreadMessageSeparator())

        // Receive an own message, e.g. sent from another device
        let ownMessage = makeMessage(id: 2, timestamp: now, actorId: activeAccount.userId, inRoom: room, withAccount: activeAccount)
        let notification = Notification(name: .NCChatControllerDidReceiveChatMessages,
                                        object: chatViewController.chatController,
                                        userInfo: ["messages": [ownMessage]])
        chatViewController.didReceiveChatMessages(notification: notification)

        // didReceiveChatMessages processes the received messages asynchronously on the main queue
        let processed = expectation(description: "Processed received messages")
        DispatchQueue.main.async { processed.fulfill() }
        wait(for: [processed], timeout: TestConstants.timeoutShort)

        // Separator removed and own message inserted in the same runloop tick. Wrong
        // coordinates would raise NSInternalInconsistencyException inside performBatchUpdates.
        XCTAssertNil(chatViewController.indexPathForUnreadMessageSeparator())
        XCTAssertEqual(tableView.numberOfSections, 1)
        XCTAssertEqual(tableView.numberOfRows(inSection: 0), 2)
        XCTAssertEqual(chatViewController.message(for: IndexPath(row: 1, section: 0))?.messageId, 2)
    }

    // Same as above, but the received messages also create a section for an older day, so the
    // batch update combines the separator removal with a section insert that shifts the
    // separator's section index.
    func testReceivedOwnMessageRemovesUnreadSeparatorWhenOlderDaySectionIsInserted() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = addRoom(withToken: "batchSeparatorShifted")
        let chatViewController = try XCTUnwrap(ChatViewController(forRoom: room, withAccount: activeAccount))
        chatViewController.loadViewIfNeeded()
        let tableView = try XCTUnwrap(chatViewController.tableView)

        let now = Int(Date().timeIntervalSince1970)

        // Existing state: only today's section, with the separator below the last message
        chatViewController.appendMessages(messages: [makeMessage(id: 100, timestamp: now - 60, actorId: "bob", inRoom: room, withAccount: activeAccount)])

        let separator = NCChatMessage()
        separator.messageId = MessageSeparatorTableViewCell.unreadMessagesSeparatorId
        let lastDateSection = try XCTUnwrap(chatViewController.dateSections.last)
        chatViewController.messages[lastDateSection]?.append(separator)

        // Force a layout pass so the reload is actually performed (see test above)
        tableView.reloadData()
        tableView.layoutIfNeeded()
        XCTAssertEqual(tableView.numberOfSections, 1)

        // A backlog message from yesterday arrives together with an own message for today,
        // so yesterday's section shifts today's section (and the separator) by one
        let backlogMessage = makeMessage(id: 99, timestamp: now - 86400, actorId: "bob", inRoom: room, withAccount: activeAccount)
        let ownMessage = makeMessage(id: 101, timestamp: now, actorId: activeAccount.userId, inRoom: room, withAccount: activeAccount)
        let notification = Notification(name: .NCChatControllerDidReceiveChatMessages,
                                        object: chatViewController.chatController,
                                        userInfo: ["messages": [backlogMessage, ownMessage]])
        chatViewController.didReceiveChatMessages(notification: notification)

        let processed = expectation(description: "Processed received messages")
        DispatchQueue.main.async { processed.fulfill() }
        wait(for: [processed], timeout: TestConstants.timeoutShort)

        XCTAssertNil(chatViewController.indexPathForUnreadMessageSeparator())
        XCTAssertEqual(tableView.numberOfSections, 2)
        XCTAssertEqual(tableView.numberOfRows(inSection: 0), 1)
        XCTAssertEqual(tableView.numberOfRows(inSection: 1), 2)
        XCTAssertEqual(chatViewController.message(for: IndexPath(row: 1, section: 1))?.messageId, 101)
    }

    private func receiveMessageWithTableViewOutOfSync(desyncMessageTimestamp: (Int) -> Int) throws -> UITableView {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let room = addRoom(withToken: "batchOutOfSync\(desyncMessageTimestamp(0))")
        let chatViewController = try XCTUnwrap(ChatViewController(forRoom: room, withAccount: activeAccount))
        chatViewController.loadViewIfNeeded()
        let tableView = try XCTUnwrap(chatViewController.tableView)

        let now = Int(Date().timeIntervalSince1970)

        chatViewController.appendMessages(messages: [makeMessage(id: 1, timestamp: now - 86400, actorId: "bob", inRoom: room, withAccount: activeAccount)])
        tableView.reloadData()
        tableView.layoutIfNeeded()
        XCTAssertEqual(tableView.numberOfSections, 1)

        // The data source grows without the tableView being told about it
        chatViewController.appendMessages(messages: [makeMessage(id: 2, timestamp: desyncMessageTimestamp(now), actorId: "bob", inRoom: room, withAccount: activeAccount)])

        let notification = Notification(name: .NCChatControllerDidReceiveChatMessages,
                                        object: chatViewController.chatController,
                                        userInfo: ["messages": [makeMessage(id: 3, timestamp: now, actorId: "bob", inRoom: room, withAccount: activeAccount)]])
        chatViewController.didReceiveChatMessages(notification: notification)

        let processed = expectation(description: "Processed received messages")
        DispatchQueue.main.async { processed.fulfill() }
        wait(for: [processed], timeout: TestConstants.timeoutShort)

        return tableView
    }

    func testReceivedMessagesWithRowsOutOfSyncDoNotRaise() throws {
        let tableView = try receiveMessageWithTableViewOutOfSync(desyncMessageTimestamp: { $0 - 86400 + 60 })

        XCTAssertEqual(tableView.numberOfSections, 2)
        XCTAssertEqual(tableView.numberOfRows(inSection: 0), 2)
        XCTAssertEqual(tableView.numberOfRows(inSection: 1), 1)
    }

    func testReceivedMessagesWithSectionsOutOfSyncDoNotRaise() throws {
        let tableView = try receiveMessageWithTableViewOutOfSync(desyncMessageTimestamp: { $0 - 60 })

        XCTAssertEqual(tableView.numberOfSections, 2)
        XCTAssertEqual(tableView.numberOfRows(inSection: 0), 1)
        XCTAssertEqual(tableView.numberOfRows(inSection: 1), 2)
    }

    private func receiveMessageAfterInvalidatingTableView(token: String, _ invalidate: (UITableView) -> Void) throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        // Unmanaged like in the app, savePendingMessage() writes to it when the window goes away
        let room = NCRoom(value: addRoom(withToken: token))
        let chatViewController = try XCTUnwrap(ChatViewController(forRoom: room, withAccount: activeAccount))

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = chatViewController
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let tableView = try XCTUnwrap(chatViewController.tableView)
        let now = Int(Date().timeIntervalSince1970)

        chatViewController.appendMessages(messages: [makeMessage(id: 1, timestamp: now - 86400, actorId: "bob", inRoom: room, withAccount: activeAccount)])
        tableView.reloadData()
        tableView.layoutIfNeeded()
        XCTAssertEqual(tableView.numberOfSections, 1)

        invalidate(tableView)

        let notification = Notification(name: .NCChatControllerDidReceiveChatMessages,
                                        object: chatViewController.chatController,
                                        userInfo: ["messages": [makeMessage(id: 2, timestamp: now, actorId: "bob", inRoom: room, withAccount: activeAccount)]])
        chatViewController.didReceiveChatMessages(notification: notification)

        let processed = expectation(description: "Processed received messages")
        DispatchQueue.main.async { processed.fulfill() }
        wait(for: [processed], timeout: TestConstants.timeoutShort)

        XCTAssertEqual(tableView.numberOfSections, 2)
    }

    func testReceivedMessagesAfterContentSizeCategoryChangeDoNotRaise() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 17, minorVersion: 0, patchVersion: 0)))

        try receiveMessageAfterInvalidatingTableView(token: "traitContentSize") { tableView in
            if #available(iOS 17.0, *) {
                tableView.traitOverrides.preferredContentSizeCategory = .accessibilityLarge
            }
        }
    }

    // MARK: - Temporary messages after the process was killed

    private let mentionParameters = "{\"mention-user1\":{\"type\":\"user\",\"id\":\"alice\",\"name\":\"Alice\"}}"
    private let fileParameters = "{\"file\":{\"type\":\"file\",\"id\":\"1\",\"name\":\"voice.mp3\",\"path\":\"/tmp/voice.mp3\"}}"

    private func enableChatReferenceId() {
        updateCapabilities { cap in
            cap.setValue([TalkCapability.chatReferenceId.rawValue], forKey: "talkCapabilities")
        }
    }

    // The reference ids are kept in a static set which lives between the tests, so every test uses unique ones
    private func uniqueReferenceId() -> String {
        return "ref-\(UUID().uuidString)"
    }

    private func addLostProcessTemporaryMessage(referenceId: String, inRoom room: NCRoom, isOffline: Bool = false, parameters: String? = nil, threadId: Int = 0) {
        let temporaryMessage = NCChatMessage()
        temporaryMessage.internalId = "temp-\(referenceId)"
        temporaryMessage.referenceId = referenceId
        temporaryMessage.accountId = room.accountId
        temporaryMessage.token = room.token
        temporaryMessage.threadId = threadId
        temporaryMessage.actorId = TestConstants.username
        temporaryMessage.actorType = "users"
        temporaryMessage.message = "Sending"
        temporaryMessage.timestamp = Int(Date().timeIntervalSince1970) - 3600
        temporaryMessage.isTemporary = true
        temporaryMessage.isOfflineMessage = isOffline

        if let parameters {
            temporaryMessage.messageParametersJSONString = parameters
        }

        try? realm.transaction {
            realm.add(temporaryMessage)
        }
    }

    private func storedTemporaryMessage(_ referenceId: String) -> NCChatMessage? {
        return NCChatMessage.objects(where: "referenceId = %@ AND isTemporary = true", referenceId).firstObject() as? NCChatMessage
    }

    func testLostTemporaryMessageIsMarkedAsFailedAfterCatchingUp() throws {
        enableChatReferenceId()
        let room = addRoom(withToken: "killedProcessRoom")
        let chatController = NCChatController(for: room)!

        // Created by an earlier process, nobody sends it anymore
        let lostId = uniqueReferenceId()
        addLostProcessTemporaryMessage(referenceId: lostId, inRoom: room)
        // A text with a mention has a message parameter, but it is no file
        let mentionId = uniqueReferenceId()
        addLostProcessTemporaryMessage(referenceId: mentionId, inRoom: room, parameters: mentionParameters)
        // Waits to be resent
        let offlineId = uniqueReferenceId()
        addLostProcessTemporaryMessage(referenceId: offlineId, inRoom: room, isOffline: true)

        // Loading the chat does not decide anything, the server copy might be still missing
        let temporaryMessages = chatController.getTemporaryMessages()
        XCTAssertEqual(temporaryMessages.count, 3)
        XCTAssertFalse(try XCTUnwrap(storedTemporaryMessage(lostId)).sendingFailed)

        var notifiedReferenceIds: [String] = []
        let observer = NotificationCenter.default.addObserver(forName: .NCChatControllerDidSendChatMessage, object: chatController, queue: nil) { notification in
            XCTAssertNotNil(notification.userInfo?["error"])
            notifiedReferenceIds.append(notification.userInfo?["referenceId"] as? String ?? "")
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        chatController.failTemporaryMessagesLostByKilledProcess(createdBefore: Int(Date().timeIntervalSince1970))

        let lost = try XCTUnwrap(storedTemporaryMessage(lostId))
        XCTAssertTrue(lost.sendingFailed)
        XCTAssertFalse(lost.isOfflineMessage)

        let offline = try XCTUnwrap(storedTemporaryMessage(offlineId))
        XCTAssertFalse(offline.sendingFailed)
        XCTAssertTrue(offline.isOfflineMessage)

        XCTAssertTrue(try XCTUnwrap(storedTemporaryMessage(mentionId)).sendingFailed)

        // An open chat is informed the same way as for a failed request
        XCTAssertEqual(Set(notifiedReferenceIds), [lostId, mentionId])
        XCTAssertEqual(notifiedReferenceIds.count, 2)
    }

    func testTemporaryMessageWithReceivedServerCopyIsRemovedNotFailed() throws {
        enableChatReferenceId()
        let room = addRoom(withToken: "echoRoom")
        let chatController = NCChatController(for: room)!

        let echoedId = uniqueReferenceId()
        let lostId = uniqueReferenceId()
        addLostProcessTemporaryMessage(referenceId: echoedId, inRoom: room)
        addLostProcessTemporaryMessage(referenceId: lostId, inRoom: room)

        // What a pull does with the server copy of the first message
        let serverCopy: [AnyHashable: Any] = [
            "id": 100,
            "token": room.token,
            "actorType": "users",
            "actorId": TestConstants.username,
            "actorDisplayName": "Me",
            "timestamp": Int(Date().timeIntervalSince1970) - 3500,
            "message": "Sending",
            "messageType": "comment",
            "referenceId": echoedId
        ]

        RLMRealm.writeTransaction { realm in
            chatController.storeMessages([serverCopy], with: realm)
        }

        chatController.failTemporaryMessagesLostByKilledProcess(createdBefore: Int(Date().timeIntervalSince1970))

        XCTAssertNil(storedTemporaryMessage(echoedId))
        XCTAssertTrue(try XCTUnwrap(storedTemporaryMessage(lostId)).sendingFailed)
    }

    func testTemporaryMessageStartedByThisProcessIsNotMarkedAsFailed() throws {
        enableChatReferenceId()
        let room = addRoom(withToken: "startedRoom")
        let chatController = NCChatController(for: room)!

        let referenceId = uniqueReferenceId()
        addLostProcessTemporaryMessage(referenceId: referenceId, inRoom: room)

        // The real entry point, it must remember the message before the request is made
        chatController.sendChatMessage("Sending", replyTo: 0, referenceId: referenceId, silently: false)

        // Control: a message nobody started is marked in the same run
        let lostId = uniqueReferenceId()
        addLostProcessTemporaryMessage(referenceId: lostId, inRoom: room)

        chatController.failTemporaryMessagesLostByKilledProcess(createdBefore: Int(Date().timeIntervalSince1970))

        XCTAssertTrue(try XCTUnwrap(storedTemporaryMessage(lostId)).sendingFailed)
        XCTAssertFalse(try XCTUnwrap(storedTemporaryMessage(referenceId)).sendingFailed)
    }

    func testFilePlaceholderIsNotMarkedAsFailed() throws {
        enableChatReferenceId()
        let room = addRoom(withToken: "fileRoom")
        let chatController = NCChatController(for: room)!

        let fileId = uniqueReferenceId()
        addLostProcessTemporaryMessage(referenceId: fileId, inRoom: room, parameters: fileParameters)

        // More than one file parameter: file() returns nil for it, but it is still a file placeholder
        let twoFilesId = uniqueReferenceId()
        let twoFiles = "{\"file1\":{\"type\":\"file\",\"id\":\"1\",\"name\":\"a.jpg\",\"path\":\"/tmp/a.jpg\"},\"file2\":{\"type\":\"file\",\"id\":\"2\",\"name\":\"b.jpg\",\"path\":\"/tmp/b.jpg\"}}"
        addLostProcessTemporaryMessage(referenceId: twoFilesId, inRoom: room, parameters: twoFiles)

        // Voice message placeholder
        let voiceId = uniqueReferenceId()
        addLostProcessTemporaryMessage(referenceId: voiceId, inRoom: room)
        try realm.transaction {
            storedTemporaryMessage(voiceId)?.messageType = kMessageTypeVoiceMessage
        }

        // Control: a lost text message in the same room is marked, so the room is set up to mark messages at all
        let textId = uniqueReferenceId()
        addLostProcessTemporaryMessage(referenceId: textId, inRoom: room)

        XCTAssertNil(storedTemporaryMessage(twoFilesId)?.file())

        chatController.failTemporaryMessagesLostByKilledProcess(createdBefore: Int(Date().timeIntervalSince1970))

        XCTAssertTrue(try XCTUnwrap(storedTemporaryMessage(textId)).sendingFailed)

        for referenceId in [fileId, twoFilesId, voiceId] {
            XCTAssertFalse(try XCTUnwrap(storedTemporaryMessage(referenceId)).sendingFailed, referenceId)
        }
    }

    func testTemporaryMessageIsNotMarkedAsFailedWithoutChatReferenceId() throws {
        // Without the capability the server copy does not remove the temporary message, so it can't be told if it was lost
        let room = addRoom(withToken: "noCapabilityRoom")
        let chatController = NCChatController(for: room)!

        let referenceId = uniqueReferenceId()
        addLostProcessTemporaryMessage(referenceId: referenceId, inRoom: room)

        chatController.failTemporaryMessagesLostByKilledProcess(createdBefore: Int(Date().timeIntervalSince1970))

        XCTAssertFalse(try XCTUnwrap(storedTemporaryMessage(referenceId)).sendingFailed)

        // Control: the same message is marked once the capability is there, so only the capability kept it untouched
        enableChatReferenceId()
        chatController.failTemporaryMessagesLostByKilledProcess(createdBefore: Int(Date().timeIntervalSince1970))

        XCTAssertTrue(try XCTUnwrap(storedTemporaryMessage(referenceId)).sendingFailed)
    }

    func testTemporaryMessageCreatedAfterThePullStartedIsNotMarkedAsFailed() throws {
        enableChatReferenceId()
        let room = addRoom(withToken: "newMessageRoom")
        let chatController = NCChatController(for: room)!

        let referenceId = uniqueReferenceId()
        addLostProcessTemporaryMessage(referenceId: referenceId, inRoom: room)

        // The message was created (1 hour ago) after the pull started (2 hours ago)
        chatController.failTemporaryMessagesLostByKilledProcess(createdBefore: Int(Date().timeIntervalSince1970) - 7200)

        XCTAssertFalse(try XCTUnwrap(storedTemporaryMessage(referenceId)).sendingFailed)

        // Control: a pull started now would have found it lost, so only the timestamp kept it untouched
        chatController.failTemporaryMessagesLostByKilledProcess(createdBefore: Int(Date().timeIntervalSince1970))

        XCTAssertTrue(try XCTUnwrap(storedTemporaryMessage(referenceId)).sendingFailed)
    }

    func testLostTemporaryMessageIsOnlyMarkedWhenCaughtUp() throws {
        enableChatReferenceId()

        struct PullResult {
            let name: String
            let statusCode: Int
            let expectedFailed: Bool
        }

        // Only a 304 proves that we caught up. A 200 answer never does, not even an empty or partial page:
        // the server drops invisible messages after applying the limit, so more messages might follow.
        let cases = [
            PullResult(name: "304", statusCode: 304, expectedFailed: true),
            PullResult(name: "200", statusCode: 200, expectedFailed: false),
            PullResult(name: "error without status code", statusCode: 0, expectedFailed: false),
            PullResult(name: "500", statusCode: 500, expectedFailed: false)
        ]

        for (index, testCase) in cases.enumerated() {
            let room = addRoom(withToken: "caughtUpRoom\(index)")
            let chatController = NCChatController(for: room)!

            let referenceId = uniqueReferenceId()
            addLostProcessTemporaryMessage(referenceId: referenceId, inRoom: room)

            chatController.failLostTemporaryMessagesIfCaughtUp(statusCode: testCase.statusCode, requestTimestamp: Int(Date().timeIntervalSince1970))

            XCTAssertEqual(try XCTUnwrap(storedTemporaryMessage(referenceId)).sendingFailed, testCase.expectedFailed, testCase.name)
        }
    }

    private func serverMessage(id: Int, referenceId: String, inRoom room: NCRoom) -> [String: Any] {
        return [
            "id": id,
            "token": room.token,
            "actorType": "users",
            "actorId": TestConstants.username,
            "actorDisplayName": "Me",
            "timestamp": Int(Date().timeIntervalSince1970) - 3500,
            "message": "Sending",
            "messageType": "comment",
            "referenceId": referenceId
        ]
    }

    /// Calls what the pull request calls with its answer. The controller is stopped, so it does not start the next pull request.
    private func handlePullResponse(of chatController: NCChatController, messages: [[String: Any]]?, statusCode: Int, requestTimestamp: Int = Int(Date().timeIntervalSince1970)) {
        chatController.stopReceivingNewChatMessages()

        let error = statusCode == 304 ? OcsError(withError: NSError(domain: NSURLErrorDomain, code: 0), withTask: nil) : nil
        chatController.handlePullResponse(messages: messages, lastKnownMessage: 0, lastCommonReadMessage: 0, error: error, statusCode: statusCode, fromMessageId: 0, requestTimestamp: requestTimestamp)
    }

    func testPullResponseWithServerCopyRemovesTemporaryMessageAndFailsOnlyTheLostOne() throws {
        enableChatReferenceId()
        let room = addRoom(withToken: "pullCopyRoom")
        let chatController = NCChatController(for: room)!

        let echoedId = uniqueReferenceId()
        let lostId = uniqueReferenceId()
        addLostProcessTemporaryMessage(referenceId: echoedId, inRoom: room)
        addLostProcessTemporaryMessage(referenceId: lostId, inRoom: room)

        // The answer with the server copy decides nothing, but stores the copy which removes its temporary message
        handlePullResponse(of: chatController, messages: [serverMessage(id: 100, referenceId: echoedId, inRoom: room)], statusCode: 200)

        XCTAssertNil(storedTemporaryMessage(echoedId))
        XCTAssertNotNil(NCChatMessage.objects(where: "referenceId = %@ AND isTemporary = false", echoedId).firstObject())
        XCTAssertFalse(try XCTUnwrap(storedTemporaryMessage(lostId)).sendingFailed)

        // Caught up: the message without a server copy is lost, the delivered one is not reported
        handlePullResponse(of: chatController, messages: nil, statusCode: 304)

        XCTAssertNil(storedTemporaryMessage(echoedId))
        XCTAssertTrue(try XCTUnwrap(storedTemporaryMessage(lostId)).sendingFailed)
    }

    func testPullResponseWithPartialPageDoesNotFailLostMessageUntilNotModified() throws {
        enableChatReferenceId()
        let room = addRoom(withToken: "pullPartialRoom")
        let chatController = NCChatController(for: room)!

        let lostId = uniqueReferenceId()
        addLostProcessTemporaryMessage(referenceId: lostId, inRoom: room)

        // A partial or empty page is no proof, the server drops invisible messages after applying the limit
        handlePullResponse(of: chatController, messages: [serverMessage(id: 100, referenceId: uniqueReferenceId(), inRoom: room)], statusCode: 200)
        XCTAssertFalse(try XCTUnwrap(storedTemporaryMessage(lostId)).sendingFailed)

        handlePullResponse(of: chatController, messages: [], statusCode: 200)
        XCTAssertFalse(try XCTUnwrap(storedTemporaryMessage(lostId)).sendingFailed)

        handlePullResponse(of: chatController, messages: nil, statusCode: 304)
        XCTAssertTrue(try XCTUnwrap(storedTemporaryMessage(lostId)).sendingFailed)
    }

    func testPullResponseDoesNotFailMessageCreatedAfterTheRequestStarted() throws {
        enableChatReferenceId()
        let room = addRoom(withToken: "pullTimestampRoom")
        let chatController = NCChatController(for: room)!

        let referenceId = uniqueReferenceId()
        addLostProcessTemporaryMessage(referenceId: referenceId, inRoom: room)

        // The message was created (1 hour ago) after the request started (2 hours ago)
        handlePullResponse(of: chatController, messages: nil, statusCode: 304, requestTimestamp: Int(Date().timeIntervalSince1970) - 7200)
        XCTAssertFalse(try XCTUnwrap(storedTemporaryMessage(referenceId)).sendingFailed)

        // Control: with a request started now the same message is lost
        let otherRoom = addRoom(withToken: "pullTimestampControlRoom")
        let otherController = NCChatController(for: otherRoom)!
        let otherId = uniqueReferenceId()
        addLostProcessTemporaryMessage(referenceId: otherId, inRoom: otherRoom)

        handlePullResponse(of: otherController, messages: nil, statusCode: 304)
        XCTAssertTrue(try XCTUnwrap(storedTemporaryMessage(otherId)).sendingFailed)
    }

    func testOnlyLostMessagesOfTheRoomThreadAndAccountOfTheControllerAreMarked() throws {
        enableChatReferenceId()
        let room = addRoom(withToken: "isolationRoom")
        let otherRoom = addRoom(withToken: "isolationOtherRoom")
        let otherAccountRoom = addRoom(withToken: room.token, withAccountId: "otherAccountId")
        let chatController = NCChatController(for: room)!

        let ownId = uniqueReferenceId()
        let threadId = uniqueReferenceId()
        let otherRoomId = uniqueReferenceId()
        let otherAccountId = uniqueReferenceId()
        addLostProcessTemporaryMessage(referenceId: ownId, inRoom: room)
        addLostProcessTemporaryMessage(referenceId: threadId, inRoom: room, threadId: 5)
        addLostProcessTemporaryMessage(referenceId: otherRoomId, inRoom: otherRoom)
        addLostProcessTemporaryMessage(referenceId: otherAccountId, inRoom: otherAccountRoom)

        var notifiedReferenceIds: [String] = []
        let observer = NotificationCenter.default.addObserver(forName: .NCChatControllerDidSendChatMessage, object: nil, queue: nil) { notification in
            notifiedReferenceIds.append(notification.userInfo?["referenceId"] as? String ?? "")
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        chatController.failTemporaryMessagesLostByKilledProcess(createdBefore: Int(Date().timeIntervalSince1970))

        XCTAssertTrue(try XCTUnwrap(storedTemporaryMessage(ownId)).sendingFailed)
        XCTAssertFalse(try XCTUnwrap(storedTemporaryMessage(threadId)).sendingFailed)
        XCTAssertFalse(try XCTUnwrap(storedTemporaryMessage(otherRoomId)).sendingFailed)
        XCTAssertFalse(try XCTUnwrap(storedTemporaryMessage(otherAccountId)).sendingFailed)
        XCTAssertEqual(notifiedReferenceIds, [ownId])
    }

    func testLostTemporaryMessagesAreOnlyCheckedOncePerController() throws {
        enableChatReferenceId()
        let room = addRoom(withToken: "checkOnceRoom")
        let chatController = NCChatController(for: room)!

        let firstId = uniqueReferenceId()
        addLostProcessTemporaryMessage(referenceId: firstId, inRoom: room)

        chatController.failLostTemporaryMessagesIfCaughtUp(statusCode: 304, requestTimestamp: Int(Date().timeIntervalSince1970))
        XCTAssertTrue(try XCTUnwrap(storedTemporaryMessage(firstId)).sendingFailed)

        // A message found later is not checked anymore, everything sent by this process is known after the first check
        let secondId = uniqueReferenceId()
        addLostProcessTemporaryMessage(referenceId: secondId, inRoom: room)

        chatController.failLostTemporaryMessagesIfCaughtUp(statusCode: 304, requestTimestamp: Int(Date().timeIntervalSince1970))
        XCTAssertFalse(try XCTUnwrap(storedTemporaryMessage(secondId)).sendingFailed)
    }
}
