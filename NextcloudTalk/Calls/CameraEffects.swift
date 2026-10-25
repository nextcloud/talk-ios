//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation

// Camera effects provided by the system: reactions triggered by hand gestures and Center Stage
enum CameraEffects {

    // The call reaction that comes closest to the effect the system shows for a recognized hand gesture.
    // Only reactions from the default set of call reactions are used.
    @available(iOS 17.0, *)
    static func callReaction(for reactionType: AVCaptureReactionType) -> String? {
        switch reactionType {
        case .thumbsUp:
            return "👍"
        case .thumbsDown:
            return "👎"
        case .heart:
            return "❤️"
        case .balloons, .confetti, .fireworks:
            return "🎉"
        case .lasers:
            return "🤩"
        case .rain:
            return "😥"
        default:
            return nil
        }
    }

    // Between two formats with the same resolution, prefer the one that supports more effects
    static func prefers(_ format: AVCaptureDevice.Format, over otherFormat: AVCaptureDevice.Format) -> Bool {
        return effectsScore(of: format) > effectsScore(of: otherFormat)
    }

    private static func effectsScore(of format: AVCaptureDevice.Format) -> Int {
        var score = 0

        if #available(iOS 17.0, *), format.reactionEffectsSupported {
            score += 2
        }

        if format.isCenterStageSupported {
            score += 1
        }

        return score
    }
}
