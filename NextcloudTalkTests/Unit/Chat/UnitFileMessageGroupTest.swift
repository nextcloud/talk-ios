//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

/// Which consecutive file messages are shown as one upload.
final class UnitFileMessageGroupTest: TestBaseRealm {

    private let uploadA = String(repeating: "a", count: 60)
    private let uploadB = String(repeating: "b", count: 60)

    private var nextMessageId = 0

    /// One file share of an upload, or any other message when the overrides say so
    private func message(upload: String? = nil,
                         position: Int = 1,
                         text: String = "{file}",
                         overrides: [String: Any] = [:]) throws -> NCChatMessage {
        self.nextMessageId += 1

        var dict: [String: Any] = [
            "id": self.nextMessageId,
            "token": "token",
            "message": text,
            "messageType": "comment",
            "systemMessage": "",
            "actorId": "alice",
            "actorType": "users",
            "messageParameters": ["file": ["type": "file", "id": "9", "name": "IMG.jpg", "path": "IMG.jpg", "mimetype": "image/jpeg"]]
        ]

        if let upload {
            dict["referenceId"] = "\(upload)-\(String(format: "%03d", position))"
        }

        dict.merge(overrides) { _, override in override }

        return try XCTUnwrap(NCChatMessage(dictionary: dict, andAccountId: TestBaseRealm.fakeAccountId))
    }

    private func textMessage() throws -> NCChatMessage {
        return try self.message(text: "Hi", overrides: ["messageParameters": [:]])
    }

    // MARK: - What is grouped

    func testFilesOfOneUploadAreGrouped() throws {
        let messages = [try self.message(upload: self.uploadA, position: 1),
                        try self.message(upload: self.uploadA, position: 2),
                        try self.message(upload: self.uploadA, position: 3)]

        let groups = FileMessageGroup.groups(in: messages)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.messages.count, 3)
    }

    func testAFileSharedOnItsOwnStaysAnOrdinaryMessage() throws {
        let groups = FileMessageGroup.groups(in: [try self.message(upload: self.uploadA)])

        XCTAssertTrue(groups.isEmpty)
    }

    func testFilesSharedBeforeTheAgreedReferenceIdAreNotGrouped() throws {
        let messages = [try self.message(), try self.message()]

        XCTAssertTrue(FileMessageGroup.groups(in: messages).isEmpty)
    }

    /// The group is anchored on the last message, so its timestamp and read state are the newest
    func testTheGroupIsShownAsItsLastMessage() throws {
        let messages = [try self.message(upload: self.uploadA, position: 1),
                        try self.message(upload: self.uploadA, position: 2)]

        let group = try XCTUnwrap(FileMessageGroup.groups(in: messages).first)

        XCTAssertEqual(group.anchor.messageId, messages[1].messageId)
    }

    /// A client that uploads in parallel has the messages arrive in any order
    func testTilesFollowTheOrderTheFilesWereSharedIn() throws {
        let messages = [try self.message(upload: self.uploadA, position: 3),
                        try self.message(upload: self.uploadA, position: 1),
                        try self.message(upload: self.uploadA, position: 2)]

        let group = try XCTUnwrap(FileMessageGroup.groups(in: messages).first)

        XCTAssertEqual(group.messagesInUploadOrder.map { $0.fileUploadReference?.position }, [1, 2, 3])
        XCTAssertEqual(group.anchor.messageId, messages[2].messageId, "The anchor still follows the conversation")
    }

    /// A file that failed to upload leaves a gap, the files around it still belong together
    func testAMissingFileDoesNotSplitAnUpload() throws {
        let messages = [try self.message(upload: self.uploadA, position: 1),
                        try self.message(upload: self.uploadA, position: 3)]

        XCTAssertEqual(FileMessageGroup.groups(in: messages).count, 1)
    }

    // MARK: - What ends a group

    func testTwoUploadsAreNotMergedIntoOne() throws {
        let messages = [try self.message(upload: self.uploadA, position: 1),
                        try self.message(upload: self.uploadA, position: 2),
                        try self.message(upload: self.uploadB, position: 1),
                        try self.message(upload: self.uploadB, position: 2)]

        let groups = FileMessageGroup.groups(in: messages)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map { $0.messages.count }, [2, 2])
    }

    func testAMessageInBetweenEndsTheGroup() throws {
        let messages = [try self.message(upload: self.uploadA, position: 1),
                        try self.message(upload: self.uploadA, position: 2),
                        try self.textMessage(),
                        try self.message(upload: self.uploadA, position: 3),
                        try self.message(upload: self.uploadA, position: 4)]

        XCTAssertEqual(FileMessageGroup.groups(in: messages).map { $0.messages.count }, [2, 2])
    }

    func testAVoiceMessageInBetweenEndsTheGroup() throws {
        let messages = [try self.message(upload: self.uploadA, position: 1),
                        try self.message(upload: self.uploadA, position: 2),
                        try self.message(upload: self.uploadA, position: 3, overrides: ["messageType": "voice-message"]),
                        try self.message(upload: self.uploadA, position: 4)]

        XCTAssertEqual(FileMessageGroup.groups(in: messages).map { $0.messages.count }, [2])
    }

    /// The caption is added to the file shared last, so it is the last thing in its group
    func testACaptionEndsTheGroupItBelongsTo() throws {
        let messages = [try self.message(upload: self.uploadA, position: 1),
                        try self.message(upload: self.uploadA, position: 2, text: "Look at these {file}"),
                        try self.message(upload: self.uploadA, position: 3)]

        let groups = FileMessageGroup.groups(in: messages)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.messages.count, 2)
        XCTAssertEqual(groups.first?.anchor.message, "Look at these {file}", "The caption is the text of the group")
    }

    func testRepliesToDifferentMessagesAreNotGrouped() throws {
        let first = try self.message(upload: self.uploadA, position: 1)
        let second = try self.message(upload: self.uploadA, position: 2)
        first.parentId = "one"
        second.parentId = "another"

        XCTAssertTrue(FileMessageGroup.groups(in: [first, second]).isEmpty)
    }

    func testRepliesToTheSameMessageAreGrouped() throws {
        let first = try self.message(upload: self.uploadA, position: 1)
        let second = try self.message(upload: self.uploadA, position: 2)
        first.parentId = "one"
        second.parentId = "one"

        XCTAssertEqual(FileMessageGroup.groups(in: [first, second]).count, 1)
    }

    // MARK: - Recognizing a caption

    func testFilePlaceholdersAreNotACaption() throws {
        XCTAssertTrue(try self.message(text: "{file}").sharesFileWithoutCaption)
        XCTAssertTrue(try self.message(text: " {file} ").sharesFileWithoutCaption)
        XCTAssertTrue(try self.message(text: "{file-12}").sharesFileWithoutCaption)
        XCTAssertTrue(try self.message(text: "").sharesFileWithoutCaption)
    }

    func testTextAroundAPlaceholderIsACaption() throws {
        XCTAssertFalse(try self.message(text: "Look {file}").sharesFileWithoutCaption)
        XCTAssertFalse(try self.message(text: "{file} indeed").sharesFileWithoutCaption)
        XCTAssertFalse(try self.message(text: "{filet}").sharesFileWithoutCaption)
        XCTAssertFalse(try self.message(text: "{file-}").sharesFileWithoutCaption)
    }
}
