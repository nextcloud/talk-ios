//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

extension TestBaseRealm {

    /// A posted file of an upload, or any other message when the overrides say so.
    func fileMessage(id: Int, upload: String? = nil, position: Int = 1, text: String = "{file}", overrides: [String: Any] = [:]) throws -> NCChatMessage {
        var dict: [String: Any] = [
            "id": id,
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

    /// A file of an upload that is still being shared in the background.
    func pendingFileMessage(upload: String, position: Int) throws -> NCChatMessage {
        let message = try self.fileMessage(id: 0, upload: upload, position: position)
        message.isTemporary = true

        return message
    }
}
