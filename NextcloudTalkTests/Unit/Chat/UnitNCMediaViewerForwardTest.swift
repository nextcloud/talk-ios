//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

/// When the media viewer offers to forward the file of a message into another conversation.
final class UnitNCMediaViewerForwardTest: TestBaseRealm {

    private func viewer(for message: NCChatMessage, room: NCRoom? = nil) -> NCMediaViewerViewController {
        let room = room ?? self.addRoom(withToken: "token")

        return NCMediaViewerViewController(initialMessage: message, room: room, account: NCDatabaseManager.sharedInstance().activeAccount())
    }

    private func fileMessage(accountId: String = TestBaseRealm.fakeAccountId,
                             path: String? = "IMG.jpg",
                             overrides: [String: Any] = [:]) throws -> NCChatMessage {
        var file: [String: Any] = ["type": "file", "id": "9", "name": "IMG.jpg", "mimetype": "image/jpeg"]
        file["path"] = path

        var dict: [String: Any] = [
            "id": 1,
            "token": "token",
            "message": "{file}",
            "messageType": "comment",
            "systemMessage": "",
            "actorId": "alice",
            "actorType": "users",
            "messageParameters": ["file": file]
        ]

        dict.merge(overrides) { _, override in override }

        return try XCTUnwrap(NCChatMessage(dictionary: dict, andAccountId: accountId))
    }

    func testFileOfOwnAccountCanBeForwarded() throws {
        let message = try self.fileMessage()

        XCTAssertTrue(self.viewer(for: message).canForward(message))
    }

    func testFileWithoutPathCannotBeForwarded() throws {
        let message = try self.fileMessage(path: nil)

        XCTAssertFalse(self.viewer(for: message).canForward(message))
    }

    func testFileOfAnotherAccountCannotBeForwarded() throws {
        // The path means something only for the account of the message
        let message = try self.fileMessage(accountId: "otherAccountId")

        XCTAssertFalse(self.viewer(for: message).canForward(message))
    }

    func testDeletedMessageCannotBeForwarded() throws {
        let message = try self.fileMessage(overrides: ["messageType": "comment_deleted"])

        XCTAssertFalse(self.viewer(for: message).canForward(message))
    }

    func testFileOfFederatedRoomCannotBeForwarded() throws {
        let room = self.addRoom(withToken: "token") { room in
            room.remoteToken = "remote"
            room.remoteServer = "https://remote.example.com"
        }
        let message = try self.fileMessage()

        XCTAssertFalse(self.viewer(for: message, room: room).canForward(message))
    }
}
