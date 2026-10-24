//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

/// Reading back the upload a shared file belongs to from its reference id.
final class UnitFileUploadReferenceTest: XCTestCase {

    private let uploadHash = String(repeating: "a", count: 60)

    func testReadsBackWhatItWrote() throws {
        let written = try XCTUnwrap(FileUploadReference(uploadId: "upload", index: 4))
        let read = try XCTUnwrap(FileUploadReference(referenceId: written.referenceId))

        XCTAssertEqual(read, written)
        XCTAssertEqual(read.position, 5)
    }

    func testFilesOfTheSameUploadShareTheirHash() throws {
        let first = try XCTUnwrap(FileUploadReference(uploadId: "upload", index: 0))
        let second = try XCTUnwrap(FileUploadReference(uploadId: "upload", index: 1))

        XCTAssertEqual(first.uploadHash, second.uploadHash)
        XCTAssertNotEqual(first.position, second.position)
    }

    func testFilesOfDifferentUploadsDoNotShareTheirHash() throws {
        let first = try XCTUnwrap(FileUploadReference(uploadId: "upload", index: 0))
        let second = try XCTUnwrap(FileUploadReference(uploadId: "another upload", index: 0))

        XCTAssertNotEqual(first.uploadHash, second.uploadHash)
    }

    func testUploadsTooLargeToNumberAreNotGrouped() {
        XCTAssertNil(FileUploadReference(uploadId: "upload", index: FileUploadReference.maximumFileCount))
        XCTAssertNil(FileUploadReference(uploadId: "upload", index: -1))
    }

    // MARK: - Reference ids that are not part of an upload

    func testReferenceIdsOfOlderClientsBelongToNoUpload() {
        // What this client wrote before the format was agreed on: a plain SHA-1 and a plain SHA-256
        XCTAssertNil(FileUploadReference(referenceId: String(repeating: "a", count: 40)))
        XCTAssertNil(FileUploadReference(referenceId: String(repeating: "a", count: 64)))
    }

    func testMalformedReferenceIdsBelongToNoUpload() {
        XCTAssertNil(FileUploadReference(referenceId: nil))
        XCTAssertNil(FileUploadReference(referenceId: ""))
        XCTAssertNil(FileUploadReference(referenceId: "temp-1758012345.678"))
        // Right shape, wrong hash length
        XCTAssertNil(FileUploadReference(referenceId: "\(String(repeating: "a", count: 59))-001"))
        XCTAssertNil(FileUploadReference(referenceId: "\(String(repeating: "a", count: 61))-001"))
        // Right hash length, no usable position
        XCTAssertNil(FileUploadReference(referenceId: "\(self.uploadHash)-abc"))
        XCTAssertNil(FileUploadReference(referenceId: self.uploadHash))
        XCTAssertNil(FileUploadReference(referenceId: "\(self.uploadHash)-001-002"))
    }

    /// The other clients validate against /[a-f0-9]{60}-[0-9]{3}/, so anything this client accepts
    /// on top of that would group messages here that stay separate on web and Android.
    func testFormatIsNotAcceptedMoreLooselyThanByTheOtherClients() {
        // Uppercase hash
        XCTAssertNil(FileUploadReference(referenceId: "\(String(repeating: "A", count: 60))-001"))
        // Hash that is not hexadecimal
        XCTAssertNil(FileUploadReference(referenceId: "\(String(repeating: "z", count: 60))-001"))
        // Position that is not padded to three digits
        XCTAssertNil(FileUploadReference(referenceId: "\(self.uploadHash)-1"))
        XCTAssertNil(FileUploadReference(referenceId: "\(self.uploadHash)-0001"))
        // Position that is signed rather than a plain number
        XCTAssertNil(FileUploadReference(referenceId: "\(self.uploadHash)-+01"))
    }

    func testTwoFilesOfOneUploadAreRecognizedAsBelongingTogether() throws {
        let first = try XCTUnwrap(FileUploadReference(referenceId: "\(self.uploadHash)-001"))
        let second = try XCTUnwrap(FileUploadReference(referenceId: "\(self.uploadHash)-002"))

        XCTAssertEqual(first.uploadHash, second.uploadHash)
        XCTAssertEqual(first.position, 1)
        XCTAssertEqual(second.position, 2)
    }
}
