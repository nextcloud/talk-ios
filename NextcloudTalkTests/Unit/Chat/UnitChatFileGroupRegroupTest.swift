//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

/// Which rows have to be reloaded when the files of an upload arrive, leave or are posted.
final class UnitChatFileGroupRegroupTest: TestBaseRealm {

    private let upload = String(repeating: "a", count: 60)
    private let timestamp = Int(Date().timeIntervalSince1970) - 60

    private func chatViewController() throws -> ChatViewController {
        let room = self.addRoom(withToken: "regroup")
        let chatViewController = try XCTUnwrap(ChatViewController(forRoom: room, withAccount: NCDatabaseManager.sharedInstance().activeAccount()))
        chatViewController.loadViewIfNeeded()

        return chatViewController
    }

    /// A posted file of the upload, or a pending one with messageId 0
    private func file(_ position: Int, messageId: Int? = nil) -> NCChatMessage {
        let message = NCChatMessage()
        message.messageId = messageId ?? position
        message.isTemporary = messageId == 0
        message.internalId = message.isTemporary ? "pending-\(position)" : "internal-\(message.messageId)"
        message.accountId = TestBaseRealm.fakeAccountId
        message.actorId = "alice"
        message.actorType = "users"
        message.actorDisplayName = "Alice"
        message.timestamp = self.timestamp
        message.token = "regroup"
        message.systemMessage = ""
        message.messageType = kMessageTypeComment
        message.message = "{file}"
        message.referenceId = "\(self.upload)-\(String(format: "%03d", position))"
        message.messageParametersJSONString = "{\"file\":{\"type\":\"file\",\"id\":\"\(position)\",\"name\":\"IMG.jpg\",\"path\":\"IMG.jpg\",\"mimetype\":\"image/jpeg\"}}"

        return message
    }

    private func pendingFile(_ position: Int) -> NCChatMessage {
        return self.file(position, messageId: 0)
    }

    /// Appends the messages and returns those whose rows show something else now
    private func changedMessages(appending messages: [NCChatMessage], to chatViewController: ChatViewController) -> [NCChatMessage] {
        let snapshot = chatViewController.fileRowSnapshot()
        chatViewController.appendMessages(messages: messages)

        return chatViewController.messagesWithChangedFileRows(since: snapshot)
    }

    func testAFileJoiningAnotherReportsBothRows() throws {
        let chatViewController = try self.chatViewController()
        let first = self.file(1)
        let second = self.file(2)

        XCTAssertTrue(self.changedMessages(appending: [first], to: chatViewController).isEmpty, "A single file shows nothing but itself")

        let changedMessages = self.changedMessages(appending: [second], to: chatViewController)

        XCTAssertEqual(Set(changedMessages.map { $0.messageId }), [1, 2])
        XCTAssertTrue(chatViewController.isHiddenInFileMessageGroup(first))
        XCTAssertEqual(chatViewController.fileMessageGroup(showing: second)?.messages.count, 2)
    }

    func testRemovingTheLastFileMovesTheGroupToTheFileBefore() throws {
        let chatViewController = try self.chatViewController()
        let files = [self.file(1), self.file(2), self.file(3)]
        chatViewController.appendMessages(messages: files)

        let snapshot = chatViewController.fileRowSnapshot()
        let indexPath = try XCTUnwrap(chatViewController.indexPath(for: files[2]))
        chatViewController.removeMessageFromDataSource(at: indexPath)
        chatViewController.regroupFileMessages()
        let changedMessages = chatViewController.messagesWithChangedFileRows(since: snapshot)

        XCTAssertTrue(changedMessages.contains { $0 === files[1] })
        XCTAssertFalse(chatViewController.isHiddenInFileMessageGroup(files[1]))
        XCTAssertEqual(chatViewController.fileMessageGroup(showing: files[1])?.messages.count, 2)
    }

    /// The posted last file can be swapped into its row in place, without a reload
    func testPostingThePendingLastFileReportsNothing() throws {
        let chatViewController = try self.chatViewController()
        chatViewController.appendMessages(messages: [self.file(1), self.file(2), self.pendingFile(3)])

        let postedLastFile = self.file(3)
        let changedMessages = self.changedMessages(appending: [postedLastFile], to: chatViewController)

        XCTAssertTrue(changedMessages.isEmpty)
        XCTAssertEqual(chatViewController.fileMessageGroup(showing: postedLastFile)?.messages.count, 3)
    }

    /// The row of the group shows the posted file without its upload state now
    func testPostingAFileInTheMiddleReportsTheGroupRow() throws {
        let chatViewController = try self.chatViewController()
        let pendingLastFile = self.pendingFile(3)
        chatViewController.appendMessages(messages: [self.file(1), self.pendingFile(2), pendingLastFile])

        let changedMessages = self.changedMessages(appending: [self.file(2)], to: chatViewController)

        XCTAssertTrue(changedMessages.contains { $0 === pendingLastFile })
    }
}
