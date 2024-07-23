//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class ContextChatViewController: BaseChatViewController {

    public override func viewDidLoad() {
        super.viewDidLoad()

        self.titleView?.longPressGestureRecognizer.isEnabled = false
    }
}
