//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

/// Which rows have to be reloaded when the files of an upload arrive, leave or are posted.
final class UnitChatFileGroupRegroupTest: TestBaseRealm {

    private let upload = String(repeating: "a", count: 60)

    private func chatViewController() throws -> ChatViewController {
        let room = self.addRoom(withToken: "regroup")
        let chatViewController = try XCTUnwrap(ChatViewController(forRoom: room, withAccount: NCDatabaseManager.sharedInstance().activeAccount()))
        chatViewController.loadViewIfNeeded()

        return chatViewController
    }

    private func file(_ position: Int) throws -> NCChatMessage {
        return try self.fileMessage(id: position, upload: self.upload, position: position)
    }

    private func pendingFile(_ position: Int) throws -> NCChatMessage {
        return try self.pendingFileMessage(upload: self.upload, position: position)
    }

    func testAFileJoiningAnotherReportsBothRows() throws {
        let chatViewController = try self.chatViewController()
        let first = try self.file(1)
        let second = try self.file(2)

        let changedBySingleFile = chatViewController.messagesWithChangedFileRows { chatViewController.appendMessages(messages: [first]) }
        XCTAssertTrue(changedBySingleFile.isEmpty, "A single file shows nothing but itself")

        let changedMessages = chatViewController.messagesWithChangedFileRows { chatViewController.appendMessages(messages: [second]) }

        XCTAssertEqual(Set(changedMessages.map { $0.messageId }), [1, 2])
        XCTAssertTrue(chatViewController.isHiddenInFileMessageGroup(first))
        XCTAssertEqual(chatViewController.fileMessageGroup(showing: second)?.messages.count, 2)
    }

    func testRemovingTheLastFileMovesTheGroupToTheFileBefore() throws {
        let chatViewController = try self.chatViewController()
        let files = [try self.file(1), try self.file(2), try self.file(3)]
        chatViewController.appendMessages(messages: files)

        let indexPath = try XCTUnwrap(chatViewController.indexPath(for: files[2]))
        chatViewController.removeMessageFromDataSource(at: indexPath)
        let changedMessages = chatViewController.messagesWithChangedFileRows { chatViewController.regroupFileMessages() }

        XCTAssertTrue(changedMessages.contains { $0 === files[1] })
        XCTAssertFalse(chatViewController.isHiddenInFileMessageGroup(files[1]))
        XCTAssertEqual(chatViewController.fileMessageGroup(showing: files[1])?.messages.count, 2)
    }

    /// The posted last file can be swapped into its row in place, without a reload
    func testPostingThePendingLastFileReportsNothing() throws {
        let chatViewController = try self.chatViewController()
        chatViewController.appendMessages(messages: [try self.file(1), try self.file(2), try self.pendingFile(3)])

        let postedLastFile = try self.file(3)
        let changedMessages = chatViewController.messagesWithChangedFileRows { chatViewController.appendMessages(messages: [postedLastFile]) }

        XCTAssertTrue(changedMessages.isEmpty)
        XCTAssertEqual(chatViewController.fileMessageGroup(showing: postedLastFile)?.messages.count, 3)
    }

    /// The row of the group shows the posted file without its upload state now
    func testPostingAFileInTheMiddleReportsTheGroupRow() throws {
        let chatViewController = try self.chatViewController()
        let pendingLastFile = try self.pendingFile(3)
        chatViewController.appendMessages(messages: [try self.file(1), try self.pendingFile(2), pendingLastFile])

        let postedMiddleFile = try self.file(2)
        let changedMessages = chatViewController.messagesWithChangedFileRows { chatViewController.appendMessages(messages: [postedMiddleFile]) }

        XCTAssertTrue(changedMessages.contains { $0 === pendingLastFile })
    }
}
