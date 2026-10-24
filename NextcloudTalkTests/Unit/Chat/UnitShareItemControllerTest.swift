//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

/// Files handed to the share item controller end up as share items only when a local copy exists.
final class UnitShareItemControllerTest: XCTestCase {

    private var sourceDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        self.sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: self.sourceDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: self.sourceDirectory)

        try super.tearDownWithError()
    }

    func testAddItemWithURLKeepsALocalCopy() throws {
        let sourceURL = self.sourceDirectory.appendingPathComponent("Document.txt")
        try Data("content".utf8).write(to: sourceURL)

        let shareItemController = ShareItemController()
        shareItemController.addItem(with: sourceURL)

        let item = try XCTUnwrap(shareItemController.shareItems.first)

        XCTAssertEqual(shareItemController.shareItems.count, 1)
        XCTAssertEqual(try String(contentsOfFile: item.filePath, encoding: .utf8), "content")
    }

    func testAddItemWithMissingFileAddsNoItem() {
        let sourceURL = self.sourceDirectory.appendingPathComponent("Missing.txt")

        let shareItemController = ShareItemController()
        shareItemController.addItem(with: sourceURL)

        XCTAssertTrue(shareItemController.shareItems.isEmpty)
    }
}
