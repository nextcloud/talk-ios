//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import WebKit

class DebounceWebView: WKWebView {
    var previousPasteTimestamp: TimeInterval = .zero

    // See: https://developer.apple.com/forums/thread/696525?answerId=708067022#708067022
    override func paste(_ sender: Any?) {
        if NCUtils.isiOSAppOnMac() {
            let currentPasteTimestamp: TimeInterval = Date().timeIntervalSinceReferenceDate

            if currentPasteTimestamp - previousPasteTimestamp < 0.2 {
                return
            }

            previousPasteTimestamp = currentPasteTimestamp
        }

        super.paste(sender)
    }
}
