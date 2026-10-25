//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

// The speed voice messages and other audio files in a chat are played with.
// One setting for all conversations, as most people want long voice messages faster everywhere.
enum VoiceMessagePlaybackSpeed {

    static let speeds: [Float] = [1, 1.5, 2]

    static let didChangeNotification = Notification.Name("VoiceMessagePlaybackSpeedDidChange")

    private static let userDefaultsKey = "ncVoiceMessagePlaybackSpeed"

    static var current: Float {
        get {
            let speed = UserDefaults.standard.float(forKey: userDefaultsKey)
            return speeds.contains(speed) ? speed : 1
        }
        set {
            UserDefaults.standard.set(newValue, forKey: userDefaultsKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    /// 1× → 1.5× → 2× → 1×
    static func next(after speed: Float) -> Float {
        guard let index = speeds.firstIndex(of: speed) else { return speeds[0] }

        return speeds[(index + 1) % speeds.count]
    }

    /// "1×", "1.5×" or "1,5×", depending on the locale
    static func label(for speed: Float, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1

        let number = formatter.string(from: NSNumber(value: speed)) ?? "\(speed)"
        return "\(number)×"
    }
}
