//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

/// What the chat shows of files that are still being shared in the background.
final class UnitChatBackgroundUploadTest: XCTestCase {

    private func upload(uploaded: Bool = false, retryDate: Date? = nil) -> ChatBackgroundUpload {
        var job = ChatBackgroundUploadJob(id: UUID().uuidString,
                                          sessionIdentifier: "session",
                                          index: 0,
                                          accountId: "account",
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

        return ChatBackgroundUpload(job: job, fileURL: URL(fileURLWithPath: "/tmp/IMG.jpg"), isFailed: false)
    }

    private func message(for upload: ChatBackgroundUpload, fileSize: Int = 1) -> NCChatMessage {
        let message = NCChatMessage()
        message.isTemporary = true
        message.messageParametersJSONString = "{\"file\":{\"type\":\"file\",\"id\":\"9\",\"name\":\"IMG.jpg\",\"size\":\(fileSize)}}"
        message.backgroundUpload = upload

        return message
    }

    /// The system starts the retry then, so the file uploads again
    func testAFileIsUploadingAgainOnceItsRetryIsDue() {
        XCTAssertEqual(self.upload(retryDate: Date(timeIntervalSinceNow: -60)).state, .uploading)
    }

    // MARK: - State of the files behind a "+N" tile

    func testFilesWaitForTheEarliestRetryOfThem() {
        let earlierRetryDate = Date(timeIntervalSinceNow: 30)
        let messages = [self.message(for: self.upload(uploaded: true)),
                        self.message(for: self.upload(retryDate: Date(timeIntervalSinceNow: 60))),
                        self.message(for: self.upload(retryDate: earlierRetryDate))]

        XCTAssertEqual(messages.combinedBackgroundUploadState, .waitingForRetry(until: earlierRetryDate))
    }

    func testPostedFilesHaveNoUploadState() {
        XCTAssertNil([NCChatMessage(), NCChatMessage()].combinedBackgroundUploadState)
    }

    /// A large video counts for more than a few small photos
    func testCombinedProgressIsWeightedByFileSize() {
        // Without a session in this process, an uploading file has no known progress
        let messages = [self.message(for: self.upload(uploaded: true), fileSize: 1_000),
                        self.message(for: self.upload(), fileSize: 3_000)]

        XCTAssertEqual(messages.combinedBackgroundUploadProgress, 0.25, accuracy: 0.001)
    }
}
