//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitChatFileUploadDestinationTest: XCTestCase {

    func testDraftFolderDestination() throws {
        let destination = ChatFileUploadDestination.draftFolder(draftPath: "Talk/Room-abc123/Alice-alice/Draft/tmp.jpg",
                                                               serverPath: "/Talk/Room-abc123/Alice-alice/Draft/tmp.jpg",
                                                               serverURL: "https://cloud.example.com/remote.php/dav/files/alice/Talk/Room-abc123/Alice-alice/Draft/tmp.jpg")

        XCTAssertEqual(destination.serverPath, "/Talk/Room-abc123/Alice-alice/Draft/tmp.jpg")
        XCTAssertEqual(destination.serverURL, "https://cloud.example.com/remote.php/dav/files/alice/Talk/Room-abc123/Alice-alice/Draft/tmp.jpg")
    }

    func testAttachmentFolderDestination() throws {
        let destination = ChatFileUploadDestination.attachmentFolder(serverPath: "/Talk/photo.jpg",
                                                                    serverURL: "https://cloud.example.com/remote.php/dav/files/alice/Talk/photo.jpg")

        XCTAssertEqual(destination.serverPath, "/Talk/photo.jpg")
        XCTAssertEqual(destination.serverURL, "https://cloud.example.com/remote.php/dav/files/alice/Talk/photo.jpg")
    }
}
