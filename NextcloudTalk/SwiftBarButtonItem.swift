//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

// See: https://stackoverflow.com/a/56637655/2512312
class SwiftBarButtonItem: UIBarButtonItem {
    typealias ActionHandler = (UIBarButtonItem) -> Void

    private var actionHandler: ActionHandler?

    convenience init(image: UIImage?, style: UIBarButtonItem.Style, actionHandler: ActionHandler?) {
        self.init(image: image, style: style, target: nil, action: #selector(barButtonItemPressed(sender:)))
        target = self
        self.actionHandler = actionHandler
    }

    convenience init(title: String?, style: UIBarButtonItem.Style, actionHandler: ActionHandler?) {
        self.init(title: title, style: style, target: nil, action: #selector(barButtonItemPressed(sender:)))
        target = self
        self.actionHandler = actionHandler
    }

    convenience init(barButtonSystemItem systemItem: UIBarButtonItem.SystemItem, actionHandler: ActionHandler?) {
        self.init(barButtonSystemItem: systemItem, target: nil, action: #selector(barButtonItemPressed(sender:)))
        target = self
        self.actionHandler = actionHandler
    }

    @objc func barButtonItemPressed(sender: UIBarButtonItem) {
        actionHandler?(sender)
    }
}
