//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objc public extension NCSettingsController {

    func isEndToEndEncryptedCallingEnabled(forAccount accountId: String) -> Bool {
        return NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: accountId)?.e2eeCallsEnabled ?? false
    }

}
