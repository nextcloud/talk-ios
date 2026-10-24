//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

struct FileUploadReference: Equatable {

    /// Identifies the upload. Every file shared together carries the same one.
    let uploadHash: String

    /// Position within the upload, starting at 1.
    let position: Int

    private static let uploadHashLength = 60

    /// The format the clients agreed on in nextcloud/spreed#19040
    private static let format = /([a-f0-9]{60})-([0-9]{3})/

    /// Longer uploads would exceed the 64 characters the server keeps, and be truncated.
    static let maximumFileCount = 999

    var referenceId: String {
        "\(self.uploadHash)-\(String(format: "%03d", self.position))"
    }

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

    /// - Parameter uploadId: The same value for every file shared together, a new one per upload.
    /// - Parameter index: Zero-based.
    init?(uploadId: String, index: Int) {
        guard index >= 0, index < Self.maximumFileCount else { return nil }

        self.uploadHash = String(NCUtils.sha256(fromString: uploadId).prefix(Self.uploadHashLength))
        self.position = index + 1
    }
}
