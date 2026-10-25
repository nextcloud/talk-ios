//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

public class NCUserDefaults: NSObject {

    private static let preferredCameraFlashModeKey = "ncPreferredCameraFlashMode"
    private static let backgroundBlurEnabledKey = "ncBackgroundBlurEnabled"
    private static let includeCallsInRecentsKey = "ncIncludeCallsInRecents"
    private static let preferredCallViewModeKey = "ncPreferredCallViewMode"
    private static let speakerViewStripeHiddenKey = "ncSpeakerViewStripeHidden"
    private static let raiseToListenKey = "ncRaiseToListen"

    public static func setPreferredCameraFlashMode(_ flashMode: Int) {
        UserDefaults.standard.set(flashMode, forKey: preferredCameraFlashModeKey)
    }

    public static func preferredCameraFlashMode() -> Int {
        return UserDefaults.standard.integer(forKey: preferredCameraFlashModeKey)
    }

    public static func setBackgroundBlurEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: backgroundBlurEnabledKey)
    }

    public static func backgroundBlurEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: backgroundBlurEnabledKey)
    }

    public static func setIncludeCallsInRecentsEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: includeCallsInRecentsKey)
    }

    public static func includeCallsInRecents() -> Bool {
        // Defaults to enabled, and persists that default on first read
        guard UserDefaults.standard.object(forKey: includeCallsInRecentsKey) != nil else {
            self.setIncludeCallsInRecentsEnabled(true)

            return true
        }

        return UserDefaults.standard.bool(forKey: includeCallsInRecentsKey)
    }

    public static func setPreferredCallViewMode(_ mode: String) {
        UserDefaults.standard.set(mode, forKey: preferredCallViewModeKey)
    }

    public static func preferredCallViewMode() -> String? {
        return UserDefaults.standard.string(forKey: preferredCallViewModeKey)
    }

    public static func setSpeakerViewStripeHidden(_ hidden: Bool) {
        UserDefaults.standard.set(hidden, forKey: speakerViewStripeHiddenKey)
    }

    public static func speakerViewStripeHidden() -> Bool {
        return UserDefaults.standard.bool(forKey: speakerViewStripeHiddenKey)
    }

    public static func setRaiseToListenEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: raiseToListenKey)
    }

    // Play the newest voice message when raising the phone to the ear, enabled by default
    public static func raiseToListenEnabled() -> Bool {
        return UserDefaults.standard.object(forKey: raiseToListenKey) as? Bool ?? true
    }
}
