//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

// Central place for haptic feedback, so the same kind of action feels the same everywhere in the app.
// UIFeedbackGenerator respects the system haptics setting, there's no need for an additional check here.
@MainActor
enum HapticFeedback {

    private static let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let rigidImpactGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    /// A small tap, e.g. when sending a message or toggling a call button
    static func light() {
        lightImpactGenerator.impactOccurred()
    }

    /// A more noticeable tap for actions with a bigger effect, e.g. leaving a call
    static func medium() {
        mediumImpactGenerator.impactOccurred()
    }

    /// A short, firm tap for something snapping into place, e.g. locking a voice recording
    static func rigid() {
        rigidImpactGenerator.impactOccurred()
    }

    /// A tick for changing a selection or toggling a state, e.g. adding a conversation to favorites
    static func selection() {
        selectionGenerator.selectionChanged()
    }

    static func success() {
        notificationGenerator.notificationOccurred(.success)
    }

    static func warning() {
        notificationGenerator.notificationOccurred(.warning)
    }

    static func error() {
        notificationGenerator.notificationOccurred(.error)
    }
}
