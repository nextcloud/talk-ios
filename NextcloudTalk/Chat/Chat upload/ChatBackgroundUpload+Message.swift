//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

extension ChatBackgroundUpload {

    /// Stands in for the file's message until the server sends it. Built from the job, never stored.
    func temporaryMessage(in room: NCRoom, for account: TalkAccount) -> NCChatMessage {
        let message = NCChatMessage()

        message.backgroundUpload = self
        message.accountId = account.accountId
        message.actorDisplayName = account.userDisplayName
        message.actorId = account.userId
        message.actorType = "users"
        message.timestamp = Int(self.job.createdAt.timeIntervalSince1970)
        message.token = self.job.roomToken
        message.threadId = self.job.metadata.threadId ?? 0
        message.isThread = self.job.metadata.threadId != nil
        message.referenceId = self.job.referenceId
        message.internalId = "background-upload-\(self.job.id)"
        message.isTemporary = true
        message.sendingFailed = self.isFailed
        message.isSilent = self.job.metadata.silent
        message.messageType = kMessageTypeComment
        message.isMarkdownMessage = NCDatabaseManager.sharedInstance().roomHasTalkCapability(.markdownMessages, for: room)

        // The server posts the caption as the message, its mentions need their placeholders and parameters
        var messageParameters: [String: Any] = [:]

        if let captionMessage = self.job.captionMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !captionMessage.isEmpty {
            message.message = captionMessage

            if let data = self.job.captionMessageParameters?.data(using: .utf8),
               let mentionParameters = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                messageParameters = mentionParameters
            }
        } else if let caption = self.job.metadata.caption?.trimmingCharacters(in: .whitespaces), !caption.isEmpty {
            message.message = caption
        } else {
            message.message = "{file}"
        }

        let fileExtension = URL(fileURLWithPath: self.job.fileName).pathExtension
        let mimetype = UTType(filenameExtension: fileExtension)?.preferredMIMEType ?? "application/octet-stream"
        let size = (try? self.fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0

        // The local path makes it open like a downloaded file
        var fileParameter: [String: Any] = [
            "type": "file",
            "id": self.job.id,
            "name": self.job.fileName,
            "path": self.job.draftPath,
            "mimetype": mimetype,
            "size": size,
            // No local video thumbnails, so videos show as a file until posted
            "preview-available": NCUtils.isImage(fileType: mimetype) ? "yes" : "no",
            "fileId": self.job.id,
            "fileName": self.job.fileName,
            "filePath": self.job.draftPath,
            "fileLocalPath": self.fileURL.path
        ]

        if NCUtils.isImage(fileType: mimetype), let pixelSize = self.imagePixelSize() {
            fileParameter["width"] = Int(pixelSize.width)
            fileParameter["height"] = Int(pixelSize.height)
        }

        messageParameters["file"] = fileParameter

        if let data = try? JSONSerialization.data(withJSONObject: messageParameters) {
            message.messageParametersJSONString = String(data: data, encoding: .utf8)
        }

        return message
    }

    /// Without decoding the image.
    private func imagePixelSize() -> CGSize? {
        guard let imageSource = CGImageSourceCreateWithURL(self.fileURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }

        // Orientations 5 to 8 are rotated by 90 degrees
        if let orientation = properties[kCGImagePropertyOrientation] as? Int, orientation >= 5 {
            return CGSize(width: height, height: width)
        }

        return CGSize(width: width, height: height)
    }
}

extension ChatBackgroundUploadState {

    var isWaitingForRetry: Bool {
        if case .waitingForRetry = self {
            return true
        }

        return false
    }

    /// Shown with a clock, a tap starts it or moves it to the front
    var isWaiting: Bool {
        return self.isWaitingForRetry || self == .waitingForTurn
    }

    /// Shown instead of the progress, nil while the progress is shown.
    var symbolName: String? {
        switch self {
        case .uploading:
            // The upload waits for a network by itself, the symbol tells why nothing moves
            return NCConnectionController.shared.connectionState == .disconnected ? "wifi.slash" : nil
        case .waitingForRetry, .waitingForTurn:
            return "clock"
        case .uploaded:
            return "checkmark"
        case .failed:
            return nil
        }
    }
}

private var backgroundUploadKey: UInt8 = 0

extension NCChatMessage {

    /// Set on the temporary message of a file shared in the background, as it was when the message was built.
    /// An associated object, as a stored property would become a Realm column. Copies of the message don't carry it.
    var backgroundUpload: ChatBackgroundUpload? {
        get {
            return objc_getAssociatedObject(self, &backgroundUploadKey) as? ChatBackgroundUpload
        }
        set {
            objc_setAssociatedObject(self, &backgroundUploadKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    var backgroundUploadJobId: String? {
        return self.backgroundUpload?.job.id
    }

    var backgroundUploadState: ChatBackgroundUploadState? {
        return self.backgroundUpload?.state
    }

    /// Zero while not known, which shows a spinning indicator.
    var backgroundUploadProgress: Float {
        guard let jobId = self.backgroundUploadJobId else { return 0 }

        if self.backgroundUploadState == .uploaded {
            return 1
        }

        return ChatBackgroundUploader.shared.uploadProgress(forJobId: jobId) ?? 0
    }
}

extension Array where Element == ChatBackgroundUploadState {

    /// What one tile or list row shows for several files: a sending one first, then a waiting one, and uploaded only
    /// when all of them are.
    var combined: ChatBackgroundUploadState? {
        guard !self.isEmpty else { return nil }

        if self.contains(.uploading) {
            return .uploading
        }

        let retryDates = self.compactMap { state -> Date? in
            guard case .waitingForRetry(let retryDate) = state else { return nil }

            return retryDate
        }

        if let nextRetryDate = retryDates.min() {
            return .waitingForRetry(until: nextRetryDate)
        }

        if self.contains(.waitingForTurn) {
            return .waitingForTurn
        }

        return self.allSatisfy { $0 == .uploaded } ? .uploaded : .uploading
    }
}

extension Array where Element == NCChatMessage {

    /// Failed files never get here, they leave their group.
    var combinedBackgroundUploadState: ChatBackgroundUploadState? {
        return self.compactMap { $0.backgroundUploadState }.combined
    }

    /// Weighted by file size, so a large video counts for more than a few small photos.
    var combinedBackgroundUploadProgress: Float {
        var totalSize: Float = 0
        var sentSize: Float = 0

        for message in self where message.backgroundUploadJobId != nil {
            let size = Float(Swift.max(message.file()?.size ?? 0, 1))

            totalSize += size
            sentSize += size * message.backgroundUploadProgress
        }

        return totalSize > 0 ? sentSize / totalSize : 0
    }
}
