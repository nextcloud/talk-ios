//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitAttachmentSheetActionTest: XCTestCase {

    private func context(isCameraAvailable: Bool = true,
                         isGiphyAvailable: Bool = true,
                         hasThreadsCapability: Bool = true,
                         hasPollsCapability: Bool = true,
                         hasLocationCapability: Bool = true,
                         roomType: NCRoomType = .group,
                         isInThread: Bool = false) -> AttachmentSheetAction.Context {

        return AttachmentSheetAction.Context(isCameraAvailable: isCameraAvailable,
                                             isGiphyAvailable: isGiphyAvailable,
                                             hasThreadsCapability: hasThreadsCapability,
                                             hasPollsCapability: hasPollsCapability,
                                             hasLocationCapability: hasLocationCapability,
                                             roomType: roomType,
                                             isInThread: isInThread)
    }

    func testAllActionsInGroupConversation() throws {
        XCTAssertEqual(AttachmentSheetAction.availableActions(in: self.context()),
                       [.camera, .photoLibrary, .giphy, .files, .nextcloudFiles, .thread, .poll, .location, .contact])
        XCTAssertEqual(Set(AttachmentSheetAction.availableActions(in: self.context())), Set(AttachmentSheetAction.allCases))
    }

    func testNoCameraNoActionForCamera() throws {
        let actions = AttachmentSheetAction.availableActions(in: self.context(isCameraAvailable: false))

        XCTAssertFalse(actions.contains(.camera))
        XCTAssertTrue(actions.contains(.photoLibrary))
    }

    func testGiphyNeedsServerSupport() throws {
        XCTAssertFalse(AttachmentSheetAction.availableActions(in: self.context(isGiphyAvailable: false)).contains(.giphy))
    }

    func testBasicActionsAreAlwaysThere() throws {
        let actions = AttachmentSheetAction.availableActions(in: self.context(isCameraAvailable: false,
                                                                              isGiphyAvailable: false,
                                                                              hasThreadsCapability: false,
                                                                              hasPollsCapability: false,
                                                                              hasLocationCapability: false))

        XCTAssertEqual(actions, [.photoLibrary, .files, .nextcloudFiles, .contact])
    }

    func testCapabilitiesDecideRichObjects() throws {
        XCTAssertFalse(AttachmentSheetAction.availableActions(in: self.context(hasThreadsCapability: false)).contains(.thread))
        XCTAssertFalse(AttachmentSheetAction.availableActions(in: self.context(hasPollsCapability: false)).contains(.poll))
        XCTAssertFalse(AttachmentSheetAction.availableActions(in: self.context(hasLocationCapability: false)).contains(.location))
    }

    func testPollsAreNotAvailableInOneToOneAndNoteToSelf() throws {
        XCTAssertFalse(AttachmentSheetAction.availableActions(in: self.context(roomType: .oneToOne)).contains(.poll))
        XCTAssertFalse(AttachmentSheetAction.availableActions(in: self.context(roomType: .noteToSelf)).contains(.poll))
        XCTAssertTrue(AttachmentSheetAction.availableActions(in: self.context(roomType: .public)).contains(.poll))

        // Everything else is not influenced
        let oneToOne = AttachmentSheetAction.availableActions(in: self.context(roomType: .oneToOne))
        XCTAssertTrue(oneToOne.contains(.thread))
        XCTAssertTrue(oneToOne.contains(.location))
        XCTAssertTrue(oneToOne.contains(.contact))
    }

    func testRichObjectsAreNotAvailableInThread() throws {
        let actions = AttachmentSheetAction.availableActions(in: self.context(isInThread: true))

        XCTAssertEqual(actions, [.camera, .photoLibrary, .giphy, .files, .nextcloudFiles])
    }
}
