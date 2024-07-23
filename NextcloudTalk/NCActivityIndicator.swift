//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

@objcMembers class NCActivityIndicator: MDCActivityIndicator {

    override func willMove(toWindow newWindow: UIWindow?) {
        // Debounce the original implementation of the MDCActivityIndicator
        // When showing a view animated, willMove(toWindow:) is called twice, therefore
        // we debounce it so that the animation does not start from the beginning again

        if newWindow == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if self.window == nil {
                    // Still not moved to a window, so we stop the animation
                    super.willMove(toWindow: nil)
                }
            }
        } else {
            super.willMove(toWindow: newWindow)
        }
    }
}
