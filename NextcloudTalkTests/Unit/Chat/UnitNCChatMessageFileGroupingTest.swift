//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

/// Which messages may be shown together with the other files of their upload.
final class UnitNCChatMessageFileGroupingTest: TestBaseRealm {

    private let uploadHash = String(repeating: "a", count: 60)

    private func fileParameter(mimetype: String = "image/jpeg") -> [String: Any] {
        return ["type": "file", "id": "9", "name": "IMG_0001.jpg", "path": "IMG_0001.jpg", "mimetype": mimetype]
    }

    /// A file share as the server sends it, which the individual tests then vary
    private func message(_ overrides: [String: Any] = [:], parameters: [String: Any]? = nil) throws -> NCChatMessage {
        var dict: [String: Any] = [
            "id": 1,
            "token": "token",
            "message": "{file}",
            "messageType": "comment",
            "systemMessage": "",
            "actorId": "alice",
            "actorType": "users",
            "referenceId": "\(self.uploadHash)-001",
            "messageParameters": parameters ?? ["file": self.fileParameter()]
        ]

        dict.merge(overrides) { _, override in override }

        return try XCTUnwrap(NCChatMessage(dictionary: dict, andAccountId: TestBaseRealm.fakeAccountId))
    }

    func testAPlainFileShareOfAnUploadIsGroupable() throws {
        XCTAssertTrue(try self.message().isGroupableFileMessage)
    }

    /// The caption ends the group it belongs to, but the message is still part of it
    func testAFileSharedWithACaptionIsGroupable() throws {
        XCTAssertTrue(try self.message(["message": "Look at this {file}"]).isGroupableFileMessage)
    }

    func testFilesSharedBeforeTheAgreedReferenceIdAreNotGroupable() throws {
        XCTAssertFalse(try self.message(["referenceId": String(repeating: "a", count: 64)]).isGroupableFileMessage)
        XCTAssertFalse(try self.message(["referenceId": ""]).isGroupableFileMessage)
    }

    // MARK: - Messages rendered by a widget of their own

    func testVoiceMessagesAreNotGroupable() throws {
        XCTAssertFalse(try self.message(["messageType": "voice-message"]).isGroupableFileMessage)
    }

    func testContactCardsAreNotGroupable() throws {
        let parameters = ["file": self.fileParameter(mimetype: "text/vcard")]
        XCTAssertFalse(try self.message(parameters: parameters).isGroupableFileMessage)
    }

    /// Unlike web, this client has no audio player to preserve: a shared audio file is drawn with
    /// the ordinary file cell, so excluding it would only split uploads that contain one
    func testAudioFilesAreGroupable() throws {
        let parameters = ["file": self.fileParameter(mimetype: "audio/mpeg")]
        XCTAssertTrue(try self.message(parameters: parameters).isGroupableFileMessage)
    }

    /// The real audio widget is the voice message, which the message type already keeps out
    func testVoiceMessagesStayExcludedRegardless() throws {
        let parameters = ["file": self.fileParameter(mimetype: "audio/mpeg")]
        XCTAssertFalse(try self.message(["messageType": "voice-message"], parameters: parameters).isGroupableFileMessage)
    }

    func testLocationsAreNotGroupable() throws {
        let parameters: [String: Any] = ["object": ["type": "geo-location", "id": "geo:1,2", "name": "Somewhere"]]
        XCTAssertFalse(try self.message(parameters: parameters).isGroupableFileMessage)
    }

    // MARK: - Messages that are not a single plain file share

    func testMessagesSharingSeveralFilesAreNotGroupable() throws {
        let parameters = ["file": self.fileParameter(), "file-1": self.fileParameter()]
        XCTAssertFalse(try self.message(parameters: parameters).isGroupableFileMessage)
    }

    func testMessagesWithoutAFileAreNotGroupable() throws {
        XCTAssertFalse(try self.message(["message": "Hi"], parameters: [:]).isGroupableFileMessage)
    }

    func testSystemMessagesAreNotGroupable() throws {
        XCTAssertFalse(try self.message(["systemMessage": "call_joined"]).isGroupableFileMessage)
    }

    func testDeletedMessagesAreNotGroupable() throws {
        XCTAssertFalse(try self.message(["messageType": "comment_deleted"]).isGroupableFileMessage)
    }

    /// Shown separately so that the edit stays visible, the same way message grouping treats it
    func testEditedMessagesAreNotGroupable() throws {
        XCTAssertFalse(try self.message(["lastEditTimestamp": 1_758_012_345]).isGroupableFileMessage)
    }

    /// Shown separately so that the failure stays visible
    func testMessagesThatFailedToSendAreNotGroupable() throws {
        let message = try self.message()
        message.sendingFailed = true

        XCTAssertFalse(message.isGroupableFileMessage)
    }

    func testMessagesBeingDeletedAreNotGroupable() throws {
        let message = try self.message()
        message.isDeleting = true

        XCTAssertFalse(message.isGroupableFileMessage)
    }

    // MARK: - Files drawn on a card on their own

    /// A file the server has no preview of said no more than its name next to a generic icon the
    /// size of a photo, so it is drawn the way the files of a group are
    func testAFileWithoutAPreviewIsDrawnOnACard() throws {
        let parameters = ["file": self.fileParameter(mimetype: "text/plain")]
        XCTAssertTrue(try self.message(parameters: parameters).isFileCardMessage)
    }

    func testMediaKeepsItsPreview() throws {
        var file = self.fileParameter()
        file["preview-available"] = "yes"

        XCTAssertFalse(try self.message(parameters: ["file": file]).isFileCardMessage)
    }

    func testMediaWithoutAPreviewIsDrawnOnACard() throws {
        // A video the server cannot make a thumbnail of, which showed a generic icon before
        let parameters = ["file": self.fileParameter(mimetype: "video/quicktime")]
        XCTAssertTrue(try self.message(parameters: parameters).isFileCardMessage)
    }

    func testWidgetsOfTheirOwnAreNotDrawnOnCards() throws {
        XCTAssertFalse(try self.message(["messageType": "voice-message"]).isFileCardMessage)
        XCTAssertFalse(try self.message(parameters: ["file": self.fileParameter(mimetype: "text/vcard")]).isFileCardMessage)
    }

    /// Unlike grouping, this does not depend on the file having been shared as part of an upload
    func testAFileOfNoUploadIsStillDrawnOnACard() throws {
        let message = try self.message(["referenceId": ""], parameters: ["file": self.fileParameter(mimetype: "text/plain")])

        XCTAssertFalse(message.isGroupableFileMessage)
        XCTAssertTrue(message.isFileCardMessage)
    }

    // MARK: - Reading the upload back

    func testFilesOfOneUploadShareTheirUploadReference() throws {
        let first = try self.message(["referenceId": "\(self.uploadHash)-001"])
        let second = try self.message(["referenceId": "\(self.uploadHash)-002"])

        XCTAssertEqual(first.fileUploadReference?.uploadHash, second.fileUploadReference?.uploadHash)
        XCTAssertEqual(first.fileUploadReference?.position, 1)
        XCTAssertEqual(second.fileUploadReference?.position, 2)
    }
}
