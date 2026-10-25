//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import TipKit
import UIKit

// Small one-time hints for features that are easy to miss, shown with TipKit (iOS 17 and later).
// TipKit makes sure a tip is only shown until it was closed or the feature was used, and not too often.

@available(iOS 17.0, *)
struct DoubleTapReactionTip: Tip {
    var title: Text {
        Text(NSLocalizedString("Double tap to react", comment: "Title of a tip"))
    }

    var message: Text? {
        Text(NSLocalizedString("Double tap a message to add your favorite reaction.", comment: "Tip shown in a chat"))
    }

    var image: Image? {
        Image(systemName: "hand.tap")
    }
}

@available(iOS 17.0, *)
struct VoiceMessageTip: Tip {
    var title: Text {
        Text(NSLocalizedString("Listening to voice messages", comment: "Title of a tip"))
    }

    var message: Text? {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return Text(NSLocalizedString("Raise your phone to your ear to listen. Long press a voice message to transcribe it.", comment: "Tip shown in a chat on iPhone"))
        }

        return Text(NSLocalizedString("Long press a voice message to transcribe it.", comment: "Tip shown in a chat"))
    }

    var image: Image? {
        Image(systemName: "waveform")
    }
}

@available(iOS 17.0, *)
struct PushToTalkTip: Tip {
    // Only interesting for somebody who mutes the microphone
    @Parameter
    static var hasMutedMicrophone: Bool = false

    var title: Text {
        Text(NSLocalizedString("Hold to talk", comment: "Title of a tip"))
    }

    var message: Text? {
        Text(NSLocalizedString("While muted, hold the microphone button or the space bar to talk.", comment: "Tip shown in a call"))
    }

    var image: Image? {
        Image(systemName: "mic.fill")
    }

    var rules: [Rule] {
        #Rule(Self.$hasMutedMicrophone) { $0 == true }
    }
}

@available(iOS 17.0, *)
struct GestureReactionsTip: Tip {
    var title: Text {
        Text(NSLocalizedString("React with your hands", comment: "Title of a tip"))
    }

    var message: Text? {
        Text(NSLocalizedString("Show a thumbs up or form a heart with your hands, and everyone in the call sees your reaction.", comment: "Tip shown in a call"))
    }

    var image: Image? {
        Image(systemName: "hand.thumbsup.fill")
    }
}

@available(iOS 17.0, *)
struct WidgetTip: Tip {
    static let appOpened = Event(id: "appOpened")

    var title: Text {
        Text(NSLocalizedString("Add Talk to your Home Screen", comment: "Title of a tip"))
    }

    var message: Text? {
        Text(NSLocalizedString("Widgets show your favorite conversations and unread messages at a glance.", comment: "Tip shown in the conversation list"))
    }

    var image: Image? {
        Image(systemName: "square.grid.2x2")
    }

    // Not for the very first steps in the app
    var rules: [Rule] {
        #Rule(Self.appOpened) { $0.donations.count >= 3 }
    }
}

enum FeatureTips {

    static func configure() {
        guard #available(iOS 17.0, *) else { return }

        // UI tests should not be interrupted by tips
        if NCUtils.isTestEnvironment {
            Tips.hideAllTipsForTesting()
        }

        do {
            try Tips.configure([.displayFrequency(.daily)])
        } catch {
            NCLog.log("Could not configure tips: \(error.localizedDescription)")
        }
    }

    static func appOpened() {
        guard #available(iOS 17.0, *) else { return }

        Task {
            await WidgetTip.appOpened.donate()
        }
    }

    static func doubleTapReactionUsed() {
        guard #available(iOS 17.0, *) else { return }
        DoubleTapReactionTip().invalidate(reason: .actionPerformed)
    }

    static func voiceMessageFeatureUsed() {
        guard #available(iOS 17.0, *) else { return }
        VoiceMessageTip().invalidate(reason: .actionPerformed)
    }

    static func microphoneMuted() {
        guard #available(iOS 17.0, *) else { return }
        PushToTalkTip.hasMutedMicrophone = true
    }

    static func pushToTalkUsed() {
        guard #available(iOS 17.0, *) else { return }
        PushToTalkTip().invalidate(reason: .actionPerformed)
    }

    static func gestureReactionUsed() {
        guard #available(iOS 17.0, *) else { return }
        GestureReactionsTip().invalidate(reason: .actionPerformed)
    }
}

// Presents a tip as a popover pointing at a view, as long as TipKit wants it to be shown.
// The view controllers keep it as AnyObject, as it is only available on iOS 17.
@available(iOS 17.0, *)
@MainActor
final class TipPopoverPresenter {

    private var observationTask: Task<Void, Never>?
    private weak var popoverController: TipUIPopoverViewController?

    /// - Parameter sourceView: Called when the tip is about to be shown, returns nil when there's nothing to point at right now
    func show<T: Tip>(_ tip: T, in viewController: UIViewController, pointingAt sourceView: @escaping () -> UIView?) {
        self.stop()

        observationTask = Task { @MainActor [weak self, weak viewController] in
            for await shouldDisplay in tip.shouldDisplayUpdates {
                guard let self, let viewController else { return }

                if shouldDisplay {
                    guard self.popoverController == nil,
                          viewController.presentedViewController == nil,
                          viewController.view.window != nil,
                          let sourceView = sourceView(), sourceView.window != nil
                    else { continue }

                    let popoverController = TipUIPopoverViewController(tip, sourceItem: sourceView)
                    viewController.present(popoverController, animated: true)
                    self.popoverController = popoverController
                } else if let popoverController = self.popoverController {
                    popoverController.dismiss(animated: true)
                    self.popoverController = nil
                }
            }
        }
    }

    func stop() {
        observationTask?.cancel()
        observationTask = nil

        if let popoverController, popoverController.presentingViewController != nil {
            popoverController.dismiss(animated: false)
        }

        popoverController = nil
    }
}
