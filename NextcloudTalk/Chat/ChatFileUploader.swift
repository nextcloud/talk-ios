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
