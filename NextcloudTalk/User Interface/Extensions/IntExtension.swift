//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

extension Int {

    init?(_ value: String?) {
        guard let value else { return nil }

        self.init(value)
    }

}
