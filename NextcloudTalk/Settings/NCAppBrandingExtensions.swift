//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SwiftUI

extension NCAppBranding {

    @objc
    static func elementColorBackground() -> UIColor {
        var lightColor: UIColor
        var darkColor: UIColor

        if #available(iOS 18.0, *) {
            lightColor = NCAppBranding.elementColor().withProminence(.quaternary)
            darkColor = NCAppBranding.elementColor().withProminence(.secondary)
        } else {
            lightColor = NCAppBranding.elementColor().withAlphaComponent(0.1)
            darkColor = NCAppBranding.elementColor().withAlphaComponent(0.2)
        }

        return NCAppBranding.getDynamicColor(lightColor, withDarkMode: darkColor)
    }

}
