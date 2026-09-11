//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// The upload a shared file belongs to, encoded in the reference id of its message.
///
/// The server stores one message per shared file, so files shared in one go are only recognizable
/// as belonging together by their reference id. The clients agreed on the format `<hash>-<position>`:
/// 60 characters identifying the upload, a dash, and the position of the file within that upload,
/// padded to three digits. Reference ids that do not follow it belong to an upload of their own,
/// which is how messages from older clients keep being shown one by one.
struct FileUploadReference: Equatable {

    /// Identifies the upload. Every file shared together carries the same one.
    let uploadHash: String

    /// Position of the file within its upload, starting at 1.
    let position: Int

    private static let uploadHashLength = 60

    /// The format the clients agreed on in nextcloud/spreed#19040
    private static let format = /([a-f0-9]{60})-([0-9]{3})/

    /// The largest upload that can still be numbered within the 64 characters the server keeps of
    /// a reference id. Beyond that it truncates, which would corrupt the position.
    static let maximumFileCount = 999

    /// The reference id to post this file with.
    var referenceId: String {
        "\(self.uploadHash)-\(String(format: "%03d", self.position))"
    }

    /// Reads the upload a message belongs to.
    ///
    /// - Parameter referenceId: Reference id of the message. Returns nil when it does not follow
    ///                          the format above, in which case the file was not shared as part of
    ///                          an upload this client can recognize.
    init?(referenceId: String?) {
        guard let referenceId,
              let match = referenceId.wholeMatch(of: Self.format),
              let position = Int(match.2)
        else {
            return nil
        }

        self.uploadHash = String(match.1)
        self.position = position
    }

    /// Describes one file of an upload.
    ///
    /// - Parameter uploadId: Identifies one upload. The same value has to be used for every file
    ///                       shared together, and a different one for the next upload.
    /// - Parameter index: Zero-based position of the file within the upload. Returns nil beyond
    ///                    `maximumFileCount`, so those files are posted ungrouped rather than with
    ///                    a reference id the server would reject.
    init?(uploadId: String, index: Int) {
        guard index >= 0, index < Self.maximumFileCount else { return nil }

        self.uploadHash = String(NCUtils.sha256(fromString: uploadId).prefix(Self.uploadHashLength))
        self.position = index + 1
    }
}
