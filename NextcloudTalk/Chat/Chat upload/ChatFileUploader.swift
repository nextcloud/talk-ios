/**
 * SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import Foundation
import NextcloudKit

@objcMembers public class ChatFileUploader: NSObject {

    public static func uploadFile(localPath: String,
                                  fileServerURL: String,
                                  fileServerPath: String,
                                  draftPath: String? = nil,
                                  talkMetaData: [String: Any]?,
                                  temporaryMessage: NCChatMessage?,
                                  room: NCRoom,
                                  completion: @escaping (Int, NSString?) -> Void) {

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        NCAPIController.sharedInstance().setupNCCommunication(forAccount: activeAccount)

        NextcloudKit.shared.upload(serverUrlFileName: fileServerURL,
                                   fileNameLocalPath: localPath,
                                   taskHandler: { _ in
            NSLog("Upload task started")
        },
                                   progressHandler: { progress in
            NSLog("Upload Progress: \(progress.fractionCompleted * 100)%")
        },
                                   completionHandler: { _, _, _, _, _, _, _, error in
            NSLog("Upload completed with error code: \(error.errorCode)")

            switch error.errorCode {
            case 0:
                if let draftPath {
                    let fileName = URL(fileURLWithPath: localPath).lastPathComponent
                    NCAPIController.sharedInstance().postConversationAttachment(inRoom: room.token,
                                                                                filePath: draftPath,
                                                                                fileName: fileName,
                                                                                referenceId: temporaryMessage?.referenceId,
                                                                                talkMetaData: talkMetaData,
                                                                                forAccount: activeAccount) { error in
                        if let error {
                            NSLog("Failed to share voice message: \(error.localizedDescription)")
                            completion(403, "Failed to share voice message")
                        } else {
                            completion(200, nil)
                        }
                    }
                } else {
                    NCAPIController.sharedInstance().shareFileOrFolder(forAccount: activeAccount,
                                                                       atPath: fileServerPath,
                                                                       toRoom: room.token,
                                                                       withTalkMetaData: talkMetaData,
                                                                       withReferenceId: temporaryMessage?.referenceId) { shareError in
                        if let shareError {
                            NSLog("Failed to share voice message: \(shareError.localizedDescription)")
                            completion(403, "Failed to share voice message")
                        } else {
                            completion(200, nil)
                        }
                    }
                }
            case 404, 409:
                NCAPIController.sharedInstance().checkOrCreateAttachmentFolder(forAccount: activeAccount) { created, _ in
                    if created {
                        uploadFile(localPath: localPath, fileServerURL: fileServerURL, fileServerPath: fileServerPath, talkMetaData: talkMetaData, temporaryMessage: temporaryMessage, room: room, completion: completion)
                    } else {
                        completion(404, "Failed to check or create attachment folder")
                    }
                }
            case 507:
                completion(507, "User storage quota exceeded")
            case 429:
                completion(429, "Too many requests")
            default:
                completion(NSInteger(error.errorCode), "Failed to upload voice message with error code: \(error.errorCode)" as NSString)
            }
        })
    }
}

@MainActor
extension ChatFileUploader {

    /// Uploads a file to the server and posts it into the conversation it belongs to.
    ///
    /// - Parameter progress: Called with the fraction of the file that has been uploaded so far.
    static func upload(_ upload: ChatFileUpload, progress: ((Double) -> Void)? = nil) async throws {
        let destination = try await self.resolveDestination(for: upload)

        try await self.put(upload, to: destination, progress: progress, mayCreateAttachmentFolder: true)
        try await self.announce(upload, at: destination)
    }

    // MARK: - Destination

    /// Determines where to upload the file to, which is the only place that knows about the two
    /// different ways of getting a file into a conversation.
    private static func resolveDestination(for upload: ChatFileUpload) async throws -> ChatFileUploadDestination {
        let apiController = NCAPIController.sharedInstance()

        guard upload.room.supportsConversationSubfolders else {
            do {
                let uniqueName = try await apiController.uniqueNameForFileUpload(withName: upload.fileName, isOriginalName: true, forAccount: upload.account)

                return .attachmentFolder(serverPath: uniqueName.fileServerPath, serverURL: uniqueName.fileServerURL)
            } catch {
                throw ChatFileUploadError.destinationUnavailable(underlyingError: error)
            }
        }

        let draftFolder: String

        do {
            draftFolder = try await apiController.probeConversationAttachmentFolder(inRoom: upload.room.token, withFileNames: [upload.fileName], forAccount: upload.account).folder
        } catch {
            throw ChatFileUploadError.destinationUnavailable(underlyingError: error)
        }

        // The file is uploaded under a temporary name, it only gets its final name when the
        // attachment endpoint moves it out of the draft folder.
        let fileExtension = URL(fileURLWithPath: upload.fileName).pathExtension
        let temporaryName = UUID().uuidString + (fileExtension.isEmpty ? "" : ".\(fileExtension)")
        let draftPath = "\(draftFolder)/\(temporaryName)"
        let serverPath = "/\(draftPath)"

        guard let serverURL = apiController.serverFileURL(forfilePath: serverPath, forAccount: upload.account)
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
