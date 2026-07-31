//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitChatFileUploadMetadataTest: XCTestCase {

    func testEmptyMetadataHasNoKeys() throws {
        XCTAssertTrue(ChatFileUploadMetadata().asDictionary().isEmpty)
    }

    func testVoiceMessage() throws {
        var metaData = ChatFileUploadMetadata()
        metaData.isVoiceMessage = true

        XCTAssertEqual(metaData.asDictionary()["messageType"] as? String, kMessageTypeVoiceMessage)
    }

    func testCaptionIsTrimmed() throws {
        var metaData = ChatFileUploadMetadata()
        metaData.caption = "  Look at this  "

        XCTAssertEqual(metaData.asDictionary()["caption"] as? String, "Look at this")
    }

    func testBlankCaptionIsOmitted() throws {
        var metaData = ChatFileUploadMetadata()
        metaData.caption = "   "

        XCTAssertNil(metaData.asDictionary()["caption"])
    }

    func testSilentIsOnlySentWhenEnabled() throws {
        var metaData = ChatFileUploadMetadata()
        XCTAssertNil(metaData.asDictionary()["silent"])

        metaData.silent = true
        XCTAssertEqual(metaData.asDictionary()["silent"] as? Bool, true)
    }

    func testReplyAndThreadIdentifiers() throws {
        var metaData = ChatFileUploadMetadata()
        metaData.replyTo = 42
        metaData.replyToToken = "abcd1234"
        metaData.threadId = 7

        let dictionary = metaData.asDictionary()

        XCTAssertEqual(dictionary["replyTo"] as? Int, 42)
        XCTAssertEqual(dictionary["replyToToken"] as? String, "abcd1234")
        XCTAssertEqual(dictionary["threadId"] as? Int, 7)
    }

    func testUnsetIdentifiersAreOmitted() throws {
        let dictionary = ChatFileUploadMetadata().asDictionary()

        XCTAssertNil(dictionary["replyTo"])
        XCTAssertNil(dictionary["replyToToken"])
        XCTAssertNil(dictionary["threadId"])
        XCTAssertNil(dictionary["messageType"])
    }
}
