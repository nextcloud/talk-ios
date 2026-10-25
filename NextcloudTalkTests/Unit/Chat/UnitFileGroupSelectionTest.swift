//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

/// What picking a row of the chat selects when the row shows the files of one upload as a group.
final class UnitFileGroupSelectionTest: TestBaseRealm {

    private let uploadHash = String(repeating: "a", count: 60)

    private func file(id: Int, position: Int, hash: String? = nil, message: String = "{file}") throws -> NCChatMessage {
        let dict: [String: Any] = [
            "id": id,
            "token": "token",
            "message": message,
            "messageType": "comment",
            "systemMessage": "",
            "actorId": "alice",
            "actorType": "users",
            "referenceId": "\(hash ?? self.uploadHash)-\(String(format: "%03d", position))",
            "messageParameters": ["file": ["type": "file", "id": "\(id)", "name": "IMG_\(id).jpg", "path": "IMG_\(id).jpg", "mimetype": "image/jpeg"]]
        ]

        return try XCTUnwrap(NCChatMessage(dictionary: dict, andAccountId: TestBaseRealm.fakeAccountId))
    }

    private func text(id: Int) throws -> NCChatMessage {
        let dict: [String: Any] = ["id": id, "token": "token", "message": "Hi \(id)", "messageType": "comment", "systemMessage": "", "actorId": "alice", "actorType": "users"]
        return try XCTUnwrap(NCChatMessage(dictionary: dict, andAccountId: TestBaseRealm.fakeAccountId))
    }

    /// The lookups of the chat, built the way `regroupFileMessages` builds them
    private func lookups(for messages: [NCChatMessage]) -> (groups: [Int: FileMessageGroup], hidden: [Int: Int]) {
        var groups: [Int: FileMessageGroup] = [:]
        var hidden: [Int: Int] = [:]

        for group in FileMessageGroup.groups(in: messages) {
            groups[group.anchor.messageId] = group

            for message in group.messages where message.messageId != group.anchor.messageId {
                hidden[message.messageId] = group.anchor.messageId
            }
        }

        return (groups, hidden)
    }

    private func ids(_ messages: [NCChatMessage]) -> [Int] {
        return messages.map { $0.messageId }
    }

    // MARK: - Whole group

    /// The row of a group is the anchor, the last file, so picking the row used to pick that one file
    func testPickingTheRowOfAGroupSelectsEveryFileOfTheUpload() throws {
        let chat = [try file(id: 10, position: 1), try file(id: 11, position: 2), try file(id: 12, position: 3)]
        let lookup = self.lookups(for: chat)

        let expanded = FileMessageGroup.expandingSelection([chat[2]], in: lookup.groups, hiddenMessageIds: lookup.hidden)

        XCTAssertEqual(self.ids(expanded), [10, 11, 12])
    }

    /// A file of the group that is not the row, e.g. picked before the rest of the upload arrived
    func testPickingOnlyAHiddenFileSelectsTheWholeGroup() throws {
        let chat = [try file(id: 10, position: 1), try file(id: 11, position: 2), try file(id: 12, position: 3)]
        let lookup = self.lookups(for: chat)

        let expanded = FileMessageGroup.expandingSelection([chat[0]], in: lookup.groups, hiddenMessageIds: lookup.hidden)

        XCTAssertEqual(self.ids(expanded), [10, 11, 12])
    }

    func testAGroupIsNotSelectedTwiceWhenSeveralOfItsFilesArePicked() throws {
        let chat = [try file(id: 10, position: 1), try file(id: 11, position: 2), try file(id: 12, position: 3)]
        let lookup = self.lookups(for: chat)

        let expanded = FileMessageGroup.expandingSelection([chat[0], chat[2]], in: lookup.groups, hiddenMessageIds: lookup.hidden)

        XCTAssertEqual(self.ids(expanded), [10, 11, 12])
    }

    // MARK: - Order

    /// Files of one upload can be posted in parallel, so the id order is not the order the group shows
    func testFilesOfAGroupFollowTheOrderOfTheUpload() throws {
        let chat = [try file(id: 10, position: 2), try file(id: 11, position: 1), try file(id: 12, position: 3)]
        let lookup = self.lookups(for: chat)

        let expanded = FileMessageGroup.expandingSelection([chat[2]], in: lookup.groups, hiddenMessageIds: lookup.hidden)

        XCTAssertEqual(self.ids(expanded), [11, 10, 12])
    }

    // MARK: - Mixed with other messages

    func testTextsAroundAGroupKeepTheirPlaces() throws {
        let chat = [try text(id: 9), try file(id: 10, position: 1), try file(id: 11, position: 2), try text(id: 12)]
        let lookup = self.lookups(for: chat)

        let expanded = FileMessageGroup.expandingSelection([chat[0], chat[2], chat[3]], in: lookup.groups, hiddenMessageIds: lookup.hidden)

        XCTAssertEqual(self.ids(expanded), [9, 10, 11, 12])
    }

    func testTwoGroupsAreEachExpandedInPlace() throws {
        let other = String(repeating: "b", count: 60)
        let chat = [try file(id: 10, position: 1), try file(id: 11, position: 2, message: "Caption {file}"),
                    try file(id: 12, position: 1, hash: other), try file(id: 13, position: 2, hash: other)]
        let lookup = self.lookups(for: chat)

        let expanded = FileMessageGroup.expandingSelection([chat[1], chat[3]], in: lookup.groups, hiddenMessageIds: lookup.hidden)

        XCTAssertEqual(self.ids(expanded), [10, 11, 12, 13])
    }

    // MARK: - Not a group

    func testASingleFileAndATextAreNotChanged() throws {
        let chat = [try text(id: 9), try file(id: 10, position: 1)]
        let lookup = self.lookups(for: chat)

        let expanded = FileMessageGroup.expandingSelection(chat, in: lookup.groups, hiddenMessageIds: lookup.hidden)

        XCTAssertEqual(self.ids(expanded), [9, 10])
    }

    // MARK: - What the actions get

    /// Forward: files are left out of the forward here, so a group counts as every one of its files
    func testForwardOfAGroupCountsEveryFileAsSkipped() throws {
        let chat = [try text(id: 9), try file(id: 10, position: 1), try file(id: 11, position: 2), try file(id: 12, position: 3)]
        let lookup = self.lookups(for: chat)

        let expanded = FileMessageGroup.expandingSelection([chat[0], chat[3]], in: lookup.groups, hiddenMessageIds: lookup.hidden)
        let plan = try XCTUnwrap(ForwardPlan.make(candidates: expanded.map { ForwardPlan.Entry(id: $0.messageId, kind: $0.file() == nil ? .text : .file) }, isClassified: false, supportsFiles: false))

        XCTAssertEqual(plan.entries.map { $0.id }, [9])
        XCTAssertEqual(plan.skippedFiles, 3)
    }

    /// Copy: one line per file of the group
    func testCopyOfAGroupHasOneLinePerFile() throws {
        let chat = [try file(id: 10, position: 1), try file(id: 11, position: 2), try file(id: 12, position: 3)]
        let lookup = self.lookups(for: chat)

        let expanded = FileMessageGroup.expandingSelection([chat[2]], in: lookup.groups, hiddenMessageIds: lookup.hidden)
        let copied = MessageSelection.joinedText(of: expanded.map { $0.parsedMessage().string })

        XCTAssertEqual(copied.components(separatedBy: MessageSelection.textSeparator).count, 3)
    }
}
