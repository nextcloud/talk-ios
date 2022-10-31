//
// Copyright (c) 2022 Marcel Müller <marcel-mueller@gmx.de>
//
// Author Marcel Müller <marcel-mueller@gmx.de>
//
// GNU GPL version 3 or any later version
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
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
