//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

/// The reference id format that lets the clients recognize files shared in one go.
final class UnitChatFileUploadReferenceIdTest: XCTestCase {

    func testReferenceIdHasTheFormatSharedWithTheOtherClients() throws {
        let referenceId = try XCTUnwrap(ChatFileUpload.referenceId(uploadId: "upload", index: 0))

        // 60 characters of hash, a dash and three digits, which is what the server allows
        XCTAssertEqual(referenceId.count, 64)

        let parts = referenceId.split(separator: "-")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].count, 60)
        XCTAssertEqual(parts[1], "001")
        XCTAssertTrue(parts[0].allSatisfy(\.isHexDigit))
    }

    func testFilesOfTheSameUploadShareTheirHash() throws {
        let first = try XCTUnwrap(ChatFileUpload.referenceId(uploadId: "upload", index: 0))
        let second = try XCTUnwrap(ChatFileUpload.referenceId(uploadId: "upload", index: 1))

        XCTAssertEqual(first.prefix(60), second.prefix(60))
        XCTAssertNotEqual(first, second)
    }

    func testFilesOfDifferentUploadsDoNotShareTheirHash() throws {
        let first = try XCTUnwrap(ChatFileUpload.referenceId(uploadId: "upload", index: 0))
        let second = try XCTUnwrap(ChatFileUpload.referenceId(uploadId: "another upload", index: 0))

        XCTAssertNotEqual(first.prefix(60), second.prefix(60))
    }

    func testIndexIsPaddedToThreeDigits() throws {
        XCTAssertEqual(try XCTUnwrap(ChatFileUpload.referenceId(uploadId: "upload", index: 8)).suffix(3), "009")
        XCTAssertEqual(try XCTUnwrap(ChatFileUpload.referenceId(uploadId: "upload", index: 98)).suffix(3), "099")
        XCTAssertEqual(try XCTUnwrap(ChatFileUpload.referenceId(uploadId: "upload", index: 998)).suffix(3), "999")
    }

    func testUploadsTooLargeToNumberAreNotGrouped() {
        // A fourth digit would exceed the 64 characters the server allows
        XCTAssertNil(ChatFileUpload.referenceId(uploadId: "upload", index: 999))
        XCTAssertNil(ChatFileUpload.referenceId(uploadId: "upload", index: -1))
    }
}
