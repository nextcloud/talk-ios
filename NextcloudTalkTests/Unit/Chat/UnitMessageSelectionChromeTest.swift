//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

/// The navigation bar and the input bar while the selection mode of the chat is active:
/// the chat renews them on its own (room update, size class change), which must not end the mode visually.
final class UnitMessageSelectionChromeTest: TestBaseRealm {

    private func makeChat(token: String) throws -> (chat: ChatViewController, message: NCChatMessage) {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        // A copy: the chat changes its room (pending message) outside of a realm transaction, as in the app
        let room = NCRoom(value: addRoom(withToken: token))
        let chat = try XCTUnwrap(ChatViewController(forRoom: room, withAccount: activeAccount))
        chat.loadViewIfNeeded()

        let message = NCChatMessage()
        message.internalId = "internal-\(token)"
        message.messageId = 1
        message.accountId = activeAccount.accountId
        message.actorId = "alice"
        message.actorType = "users"
        message.actorDisplayName = "Alice"
        message.timestamp = Int(Date().timeIntervalSince1970) - 60
        message.token = room.token
        message.message = "Message 1"

        chat.appendMessages(messages: [message])
        chat.tableView?.reloadData()

        return (chat, message)
    }

    func testRenewedTitleViewDoesNotReplaceTheSelectionTitle() throws {
        let (chat, message) = try makeChat(token: "selTitle")
        let originalTitleView = try XCTUnwrap(chat.navigationItem.titleView)

        chat.beginSelectionMode(with: message)

        let selectionTitle = try XCTUnwrap(chat.selectionTitleLabel)
        XCTAssertTrue(chat.navigationItem.titleView === selectionTitle)

        // The chat renews its title view on a room update and on a change of the size class (rotation)
        chat.setTitleView()

        XCTAssertTrue(chat.navigationItem.titleView === selectionTitle, "The selection title must stay")

        chat.endSelectionMode()

        // The title view of the chat is the renewed one, not the one from before the mode
        XCTAssertTrue(chat.navigationItem.titleView === chat.titleView)
        XCTAssertFalse(chat.navigationItem.titleView === originalTitleView)
    }

    func testRoomControlsCheckDoesNotShowTheInputbarInTheSelectionMode() throws {
        let (chat, message) = try makeChat(token: "selInput")

        chat.setTextInputbarHidden(false, animated: false)
        XCTAssertFalse(chat.textInputbar.isHidden)

        chat.beginSelectionMode(with: message)
        XCTAssertTrue(chat.textInputbar.isHidden)

        // Runs on every update of the room
        chat.checkRoomControlsAvailability()

        XCTAssertTrue(chat.textInputbar.isHidden, "The input bar would be shown over the action bar of the selection")

        chat.endSelectionMode()

        XCTAssertFalse(chat.textInputbar.isHidden)
    }

    func testDraftIsSavedWhenTheChatDisappearsInTheSelectionMode() throws {
        let (chat, message) = try makeChat(token: "selDraft")

        chat.textView.text = "A draft"
        chat.beginSelectionMode(with: message)

        chat.viewWillDisappear(false)

        XCTAssertEqual(chat.room.pendingMessage, "A draft")
    }

    func testStringsOfTheSelectionArePluralized() {
        XCTAssertEqual(String.localizedStringWithFormat(NSLocalizedString("%ld selected", comment: ""), 3), "3 selected")
        XCTAssertEqual(String.localizedStringWithFormat(NSLocalizedString("%ld files were not forwarded", comment: ""), 1), "1 file was not forwarded")
        XCTAssertEqual(String.localizedStringWithFormat(NSLocalizedString("%ld files were not forwarded", comment: ""), 4), "4 files were not forwarded")
        XCTAssertEqual(String.localizedStringWithFormat(NSLocalizedString("Forwarded %1$ld of %2$ld messages", comment: ""), 2, 5), "Forwarded 2 of 5 messages")
    }
}
