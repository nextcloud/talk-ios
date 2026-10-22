//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Photos

///
/// Saves a picture or a video file to the photo library.
///
/// Only asks for add-only access, so the app never gets to read the library through this.
///
enum MediaPhotoLibrarySaver {

    enum SaveError: Error {
        case accessDenied
        case failed
    }

    ///
    /// Adds the file to the photo library, a video as a video and everything else as a picture.
    ///
    /// The completion is always called on the main queue.
    ///
    static func save(fileURL: URL, isVideo: Bool, completion: @escaping (Result<Void, SaveError>) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(.failure(.accessDenied)) }
                return
            }

            PHPhotoLibrary.shared().performChanges({
                if isVideo {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                } else {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
                }
            }, completionHandler: { success, _ in
                DispatchQueue.main.async { completion(success ? .success(()) : .failure(.failed)) }
            })
        }
    }
}
