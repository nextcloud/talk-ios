//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// A recorder that was told to stop still finishes its file, and then gives the shared audio session back.
/// A new recording must not start before that, as it would lose its audio session to the one of the old recorder.
struct VideoMessageStopTracker {

    private var pendingStops = 0

    /// True from the moment a recorder is told to stop until it has finished and restored the audio session
    var isStopping: Bool {
        return self.pendingStops > 0
    }

    mutating func stopBegan() {
        self.pendingStops += 1
    }

    mutating func stopEnded() {
        self.pendingStops = max(self.pendingStops - 1, 0)
    }
}
