//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import CarPlay
import Intents
import UIKit

@available(iOS 14.0, *)
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        NCLog.log("CarPlay scene connected")
        CarPlayManager.shared.connect(interfaceController)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        NCLog.log("CarPlay scene disconnected")
        CarPlayManager.shared.disconnect()
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        NCLog.log("CarPlay scene received user activity type=\(userActivity.activityType)")

        guard let interaction = userActivity.interaction else {
            NCLog.log("CarPlay scene user activity has no interaction")
            return
        }

        guard let startCallIntent = interaction.intent as? INStartCallIntent else {
            NCLog.log(
                "CarPlay scene received unsupported intent: \(String(describing: type(of: interaction.intent)))"
            )
            return
        }

        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            NCLog.log("CarPlay scene could not access AppDelegate")
            return
        }

        NCLog.log(
            "CarPlay scene forwarding INStartCallIntent contacts=\(startCallIntent.contacts?.count ?? 0)"
        )

        _ = appDelegate.handleStartCallIntent(startCallIntent)
    }
}

