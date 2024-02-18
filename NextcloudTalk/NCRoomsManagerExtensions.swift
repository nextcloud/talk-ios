//
// Copyright (c) 2024 Marcel Müller <marcel-mueller@gmx.de>
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

import Foundation

@objc extension NCRoomsManager {

    public func checkUpdateNeededForPendingFederationInvitations() {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let tenMinutesAgo = Int(Date().timeIntervalSince1970 - (10 * 60))

        if activeAccount.lastPendingFederationInvitationFetch == 0 || activeAccount.lastPendingFederationInvitationFetch < tenMinutesAgo {
            self.updatePendingFederationInvitations()
        }
    }

    public func updatePendingFederationInvitations() {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        NCAPIController.sharedInstance().getFederationInvitations(for: activeAccount.accountId) { invitations in
            guard let invitations else { return }
            let pendingInvitations = invitations.filter { $0.invitationState != .accepted }

            if activeAccount.pendingFederationInvitations != pendingInvitations.count {
                NCDatabaseManager.sharedInstance().setPendingFederationInvitationForAccountId(activeAccount.accountId, with: pendingInvitations.count)
            }
        }
    }
}
