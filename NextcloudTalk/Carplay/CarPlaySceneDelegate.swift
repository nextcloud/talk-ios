//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import CarPlay
import UIKit

@available(iOS 14.0, *)
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    override init() {
        super.init()
    }

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
        NCLog.log("CarPlay scene received user activity type=\(userActivity.activityType)")

        guard let intent = userActivity.interaction?.intent else {
            NCLog.log("CarPlay scene user activity has no intent")
            return
        }

        guard let startCallIntent = intent as? INStartCallIntent else {
            NCLog.log(
                "CarPlay scene received unsupported intent: \(String(describing: type(of: intent)))"
            )
            return
        }

        guard
            let appDelegate = UIApplication.shared.delegate as? AppDelegate
        else {
            NCLog.log("CarPlay scene could not access AppDelegate")
            return
        }

        Task { @MainActor in
            _ = appDelegate.handleStartCallIntent(startCallIntent)
        }
    }
}
