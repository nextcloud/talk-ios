//
// Copyright (c) 2024 Marcel Müller <marcel.mueller@nextcloud.com>
//
// Author Marcel Müller <marcel.mueller@nextcloud.com>
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
