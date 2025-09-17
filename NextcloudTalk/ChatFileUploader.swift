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
                                  talkMetaData: [String: Any]?,
                                  temporaryMessage: NCChatMessage?,
                                  room: NCRoom,
                                  completion: @escaping (Int, NSString?) -> Void) {

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        NCAPIController.sharedInstance().setupNCCommunication(for: activeAccount)

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
                NCAPIController.sharedInstance().shareFileOrFolder(for: activeAccount,
                                                                   atPath: fileServerPath,
                                                                   toRoom: room.token,
                                                                   talkMetaData: talkMetaData,
                                                                   referenceId: temporaryMessage?.referenceId) { shareError in
                    if let shareError = shareError {
                        NSLog("Failed to share voice message: \(shareError.localizedDescription)")
                        completion(403, "Failed to share voice message")
                    } else {
                        completion(200, nil)
                    }
                }
            case 404, 409:
                NCAPIController.sharedInstance().checkOrCreateAttachmentFolder(for: activeAccount) { created, _ in
                    if created {
                        uploadFile(localPath: localPath, fileServerURL: fileServerURL, fileServerPath: fileServerPath, talkMetaData: talkMetaData, temporaryMessage: temporaryMessage, room: room, completion: completion)
                    } else {
                        completion(404, "Failed to check or create attachment folder")
                    }
                }
            case 507:
                completion(507, "User storage quota exceeded")
            default:
                completion(NSInteger(error.errorCode), "Failed to upload voice message with error code: \(error.errorCode)" as NSString)
            }
        })
    }
}
