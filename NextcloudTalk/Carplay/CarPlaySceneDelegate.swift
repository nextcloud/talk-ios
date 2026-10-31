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
        CarPlayManager.shared.connect(interfaceController)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        CarPlayManager.shared.disconnect()
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard let startCallIntent = userActivity.interaction?.intent as? INStartCallIntent,
              let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            return
        }

        _ = appDelegate.handleStartCallIntent(startCallIntent)
    }
}
