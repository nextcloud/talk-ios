//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import AVKit

extension AVRoutePickerView {
    func showPicker() {
        self.subviews.compactMap { $0 as? UIButton } .forEach { $0.sendActions(for: .touchUpInside )}
    }
}
