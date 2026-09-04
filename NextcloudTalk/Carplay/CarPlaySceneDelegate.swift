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
        print("### CARPLAY SCENE DELEGATE CREATED ###")
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        print("### CARPLAY CONNECTED ###")

        CarPlayManager.shared.connect(interfaceController)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        print("### CARPLAY DISCONNECTED ###")

        CarPlayManager.shared.disconnect()
    }
}
