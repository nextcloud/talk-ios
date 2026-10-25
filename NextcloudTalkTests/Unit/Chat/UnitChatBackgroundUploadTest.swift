//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

/// What the chat shows of files that are still being shared in the background.
final class UnitChatBackgroundUploadTest: TestBaseRealm {

    private func upload(uploaded: Bool = false, retryDate: Date? = nil, isFailed: Bool = false) -> ChatBackgroundUpload {
        var job = ChatBackgroundUploadJob(id: UUID().uuidString,
                                          sessionIdentifier: "session",
                                          index: 0,
                                          accountId: TestBaseRealm.fakeAccountId,
                                          roomToken: "token",
                                          roomName: "Room",
                                          fileName: "IMG.jpg",
                                          draftPath: "Talk/Drafts/IMG.jpg",
                                          serverURL: "https://example.com/IMG.jpg",
                                          referenceId: nil,
                                          metadata: ChatFileUploadMetadata(),
                                          allowUpdate: false,
                                          createdAt: Date())
        job.uploaded = uploaded
        job.uploadRetryDate = retryDate

        return ChatBackgroundUpload(job: job, fileURL: URL(fileURLWithPath: "/tmp/IMG.jpg"), isFailed: isFailed)
    }

    private func message(for upload: ChatBackgroundUpload) -> NCChatMessage {
        let message = NCChatMessage()
        message.isTemporary = true
        message.backgroundUpload = upload

        return message
    }

    // MARK: - State of one file

    func testAFileIsUploadingUntilItIsOnTheServer() {
        XCTAssertEqual(self.upload().state, .uploading)
    }

    func testAnUploadedFileWaitsForBeingPosted() {
        XCTAssertEqual(self.upload(uploaded: true).state, .uploaded)
    }

    func testAFailedFileStaysFailed() {
        XCTAssertEqual(self.upload(uploaded: true, isFailed: true).state, .failed)
    }

    func testAFileWaitsUntilItsRetry() {
        let retryDate = Date(timeIntervalSinceNow: 60)

        XCTAssertEqual(self.upload(retryDate: retryDate).state, .waitingForRetry(until: retryDate))
    }

    /// The system starts the retry then, so the file uploads again
    func testAFileIsUploadingAgainOnceItsRetryIsDue() {
        XCTAssertEqual(self.upload(retryDate: Date(timeIntervalSinceNow: -60)).state, .uploading)
    }

    // MARK: - State of the files behind a "+N" tile

    func testFilesAreUploadingWhileOneOfThemIs() {
        let messages = [self.message(for: self.upload(uploaded: true)), self.message(for: self.upload())]

        XCTAssertEqual(messages.combinedBackgroundUploadState, .uploading)
    }

    func testFilesAreUploadedOnceAllOfThemAre() {
        let messages = [self.message(for: self.upload(uploaded: true)), self.message(for: self.upload(uploaded: true))]

        XCTAssertEqual(messages.combinedBackgroundUploadState, .uploaded)
    }

    func testFilesWaitForTheEarliestRetryOfThem() {
        let earlierRetryDate = Date(timeIntervalSinceNow: 30)
        let messages = [self.message(for: self.upload()),
                        self.message(for: self.upload(retryDate: Date(timeIntervalSinceNow: 60))),
                        self.message(for: self.upload(retryDate: earlierRetryDate))]

        XCTAssertEqual(messages.combinedBackgroundUploadState, .waitingForRetry(until: earlierRetryDate))
    }

    func testPostedFilesHaveNoUploadState() {
        XCTAssertNil([NCChatMessage(), NCChatMessage()].combinedBackgroundUploadState)
    }

    func testCombinedProgressCountsUploadedFilesAsDone() {
        // Without a session in this process, an uploading file has no known progress
        let messages = [self.message(for: self.upload(uploaded: true)), self.message(for: self.upload())]

        XCTAssertEqual(messages.combinedBackgroundUploadProgress, 0.5, accuracy: 0.001)
    }
}
