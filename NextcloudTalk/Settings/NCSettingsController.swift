//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objc public extension NCSettingsController {

    func isEndToEndEncryptedCallingEnabled(forAccount accountId: String) -> Bool {
        return NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: accountId)?.e2eeCallsEnabled ?? false
    }

    func isRoomsSortingSupported(forAccountId accountId: String) -> Bool {
        guard let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: accountId)
        else { return false }

        return NCRoomSortOrder(rawValue: serverCapabilities.roomsSortOrder) != .unsupported &&
        NCRoomGroupMode(rawValue: serverCapabilities.roomsGroupMode) != .unsupported
    }

}
