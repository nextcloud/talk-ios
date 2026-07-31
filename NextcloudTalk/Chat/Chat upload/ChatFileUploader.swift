/**
 * SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import Foundation
import NextcloudKit

/// Uploads files to the server and posts them into a conversation.
@MainActor
enum ChatFileUploader {

    /// Uploads a file to the server and posts it into the conversation it belongs to.
    ///
    /// - Parameter progress: Called with the fraction of the file that has been uploaded so far.
    static func upload(_ upload: ChatFileUpload, progress: ((Double) -> Void)? = nil) async throws {
        let destination = try await self.resolveDestination(for: upload)

        try await self.put(upload, to: destination, progress: progress, mayCreateAttachmentFolder: true)
        try await self.announce(upload, at: destination)
    }

    /// Uploads several files to the server and posts them into the conversation they belong to.
    ///
    /// All uploads need to be for the same conversation and account: with conversation subfolders
    /// enabled, the draft folder is requested once for all of them.
    ///
    /// - Parameter progress: Called with the index of an upload and the fraction of it that has been
    ///                       uploaded so far.
    /// - Throws: When the draft folder could not be prepared, in which case nothing was uploaded.
    /// - Returns: One result per upload, in the order the uploads were given in.
    static func upload(_ uploads: [ChatFileUpload],
                       progress: ((_ index: Int, _ fractionCompleted: Double) -> Void)? = nil) async throws -> [Result<Void, Error>] {
        guard let firstUpload = uploads.first else { return [] }

        // One draft folder is enough for the whole batch, so it is requested before uploading
        // anything: without it there is nowhere to upload to at all.
        var draftFolder: String?

        if firstUpload.room.supportsConversationSubfolders {
            draftFolder = try await self.probeDraftFolder(for: firstUpload.room,
                                                          account: firstUpload.account,
                                                          fileNames: uploads.map { $0.fileName })
        }

        return await withTaskGroup(of: (index: Int, result: Result<Void, Error>).self) { group in
            for (index, upload) in uploads.enumerated() {
                group.addTask {
                    do {
                        let destination: ChatFileUploadDestination

                        if let draftFolder {
                            destination = try await self.draftFolderDestination(in: draftFolder, for: upload)
                        } else {
                            destination = try await self.resolveDestination(for: upload)
                        }

                        try await self.put(upload, to: destination, progress: { progress?(index, $0) }, mayCreateAttachmentFolder: true)
                        try await self.announce(upload, at: destination)

                        return (index, .success(()))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }

            var results = [Result<Void, Error>](repeating: .success(()), count: uploads.count)

            for await taskResult in group {
                results[taskResult.index] = taskResult.result
            }

            return results
        }
    }

    // MARK: - Destination

    /// Determines where to upload the file to, which is the only place that knows about the two
    /// different ways of getting a file into a conversation.
    private static func resolveDestination(for upload: ChatFileUpload) async throws -> ChatFileUploadDestination {
        guard upload.room.supportsConversationSubfolders else {
            do {
                let uniqueName = try await NCAPIController.sharedInstance().uniqueNameForFileUpload(withName: upload.fileName, isOriginalName: true, forAccount: upload.account)

                return .attachmentFolder(serverPath: uniqueName.fileServerPath, serverURL: uniqueName.fileServerURL)
            } catch {
                throw ChatFileUploadError.destinationUnavailable(underlyingError: error)
            }
        }

        let draftFolder = try await self.probeDraftFolder(for: upload.room, account: upload.account, fileNames: [upload.fileName])

        return try await self.draftFolderDestination(in: draftFolder, for: upload)
    }

    /// Makes sure the conversation subfolder exists and returns the draft folder to upload into.
    private static func probeDraftFolder(for room: NCRoom, account: TalkAccount, fileNames: [String]) async throws -> String {
        do {
            return try await NCAPIController.sharedInstance().probeConversationAttachmentFolder(inRoom: room.token, withFileNames: fileNames, forAccount: account).folder
        } catch {
            throw ChatFileUploadError.destinationUnavailable(underlyingError: error)
        }
    }

    private static func draftFolderDestination(in draftFolder: String, for upload: ChatFileUpload) async throws -> ChatFileUploadDestination {
        // The file is uploaded under a temporary name, it only gets its final name when the
        // attachment endpoint moves it out of the draft folder.
        let fileExtension = URL(fileURLWithPath: upload.fileName).pathExtension
        let temporaryName = UUID().uuidString + (fileExtension.isEmpty ? "" : ".\(fileExtension)")
        let draftPath = "\(draftFolder)/\(temporaryName)"
        let serverPath = "/\(draftPath)"

        guard let serverURL = NCAPIController.sharedInstance().serverFileURL(forfilePath: serverPath, forAccount: upload.account)
        else { throw ChatFileUploadError.destinationUnavailable(underlyingError: nil) }

        return .draftFolder(draftPath: draftPath, serverPath: serverPath, serverURL: serverURL)
    }

    // MARK: - Upload

    private static func put(_ upload: ChatFileUpload,
                            to destination: ChatFileUploadDestination,
                            progress: ((Double) -> Void)?,
                            mayCreateAttachmentFolder: Bool) async throws {
        let apiController = NCAPIController.sharedInstance()
        apiController.setupNCCommunication(forAccount: upload.account)

        do {
            try await self.putFile(upload, to: destination, progress: progress)
        } catch let error as ChatFileUploadError {
            // A missing folder can only happen in the attachment folder flow, as the draft folder
            // is created by the probe request while resolving the destination.
            guard mayCreateAttachmentFolder,
                  case .attachmentFolder = destination,
                  case .uploadFailed(let errorCode, _) = error,
                  errorCode == 404 || errorCode == 409
            else { throw error }

            guard await apiController.checkOrCreateAttachmentFolder(forAccount: upload.account)
            else { throw ChatFileUploadError.attachmentFolderUnavailable }

            // Retry into the same destination, the name we picked before is still free
            try await self.put(upload, to: destination, progress: progress, mayCreateAttachmentFolder: false)
        }
    }

    private static func putFile(_ upload: ChatFileUpload,
                                to destination: ChatFileUploadDestination,
                                progress: ((Double) -> Void)?) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            NextcloudKit.shared.upload(serverUrlFileName: destination.serverURL,
                                       fileNameLocalPath: upload.localPath,
                                       progressHandler: { uploadProgress in
                progress?(uploadProgress.fractionCompleted)
            }, completionHandler: { _, _, _, _, _, _, error in
                switch error.errorCode {
                case 0:
                    continuation.resume()
                case 507:
                    continuation.resume(throwing: ChatFileUploadError.quotaExceeded)
                case 429:
                    continuation.resume(throwing: ChatFileUploadError.tooManyRequests)
                default:
                    continuation.resume(throwing: ChatFileUploadError.uploadFailed(errorCode: error.errorCode, errorDescription: error.errorDescription))
                }
            })
        }
    }

    // MARK: - Announce

    /// Posts the already uploaded file as a message into the conversation.
    private static func announce(_ upload: ChatFileUpload, at destination: ChatFileUploadDestination) async throws {
        let apiController = NCAPIController.sharedInstance()
        let talkMetaData = upload.metadata.asDictionary()

        do {
            switch destination {
            case .draftFolder(let draftPath, _, _):
                try await apiController.postConversationAttachment(inRoom: upload.room.token,
                                                                   filePath: draftPath,
                                                                   fileName: upload.fileName,
                                                                   referenceId: upload.referenceId,
                                                                   talkMetaData: talkMetaData,
                                                                   forAccount: upload.account)
            case .attachmentFolder(let serverPath, _):
                try await apiController.shareFileOrFolder(forAccount: upload.account,
                                                          atPath: serverPath,
                                                          toRoom: upload.room.token,
                                                          withTalkMetaData: talkMetaData,
                                                          withReferenceId: upload.referenceId)
            }
        } catch {
            throw ChatFileUploadError.shareFailed(underlyingError: error)
        }
    }
}
