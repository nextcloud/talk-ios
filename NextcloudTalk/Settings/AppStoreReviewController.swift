//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import StoreKit

@objcMembers class AppStoreReviewController: NSObject {

    static let addReaction = "reactionsCountForAppStoreReview"
    static let updateStatus = "statusUpdatesCountForAppStoreReview"
    static let visitAppSettings = "settingsVisitsCountForAppStoreReview"

    static let allTrackedActions = [
        addReaction,
        updateStatus,
        visitAppSettings
    ]

    // Number of times each action must occur before asking for a review
    private static let reviewThresholds: [String: Int] = [
        addReaction: 5,
        updateStatus: 3,
        visitAppSettings: 3
    ]

    private static let lastRequestedReviewAppVersion = "lastRequestedReviewAppVersion"

    static func recordAction(_ action: String) {
        // Do not request reviews for branded apps
        if isBrandedApp.boolValue {
            return
        }

        let currentAppVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let lastRequestedAppVersion = UserDefaults.standard.string(forKey: lastRequestedReviewAppVersion)

        // If a review was already requested for this version, do nothing
        if lastRequestedAppVersion == currentAppVersion {
            return
        }

        // Increment the action's counter
        let currentCount = UserDefaults.standard.integer(forKey: action)
        UserDefaults.standard.set(currentCount + 1, forKey: action)

        // Check if threshold is reached to request a review
        if let threshold = reviewThresholds[action], currentCount + 1 >= threshold {
            requestReviewInCurrentScene(for: currentAppVersion)
        }
    }

    private static func requestReviewInCurrentScene(for appVersion: String) {
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            DispatchQueue.main.async {
                SKStoreReviewController.requestReview(in: scene)
                UserDefaults.standard.set(appVersion, forKey: lastRequestedReviewAppVersion)
                resetActionCounters()
            }
        }
    }

    private static func resetActionCounters() {
        for action in allTrackedActions {
            UserDefaults.standard.set(0, forKey: action)
        }
    }
}
