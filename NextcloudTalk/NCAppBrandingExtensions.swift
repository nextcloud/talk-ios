//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SwiftUI

extension NCAppBranding {

    @objc
    static func themeColorBackground() -> UIColor {
        var lightColor: UIColor
        var darkColor: UIColor

        if #available(iOS 18.0, *) {
            lightColor = NCAppBranding.themeColor().withProminence(.quaternary)
            darkColor = NCAppBranding.themeColor().withProminence(.secondary)
        } else {
            lightColor = NCAppBranding.themeColor().withAlphaComponent(0.1)
            darkColor = NCAppBranding.themeColor().withAlphaComponent(0.2)
        }

        return NCAppBranding.getDynamicColor(lightColor, withDarkMode: darkColor)
    }

}
