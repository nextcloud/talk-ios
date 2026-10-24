//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SwiftUI
import UIKit

struct ContactsTableViewCellWrapper: UIViewRepresentable {
    @Binding var room: NCRoom
    @Binding var participant: NCRoomParticipant

    func makeUIView(context: Context) -> ContactsTableViewCell {
        let cell: ContactsTableViewCell = .fromNib()
        cell.translatesAutoresizingMaskIntoConstraints = false

        return cell
    }

    func updateUIView(_ cell: ContactsTableViewCell, context: Context) {
        cell.labelTitle.text = participant.detailedName

        let roleIcon = participant.roleIcon(in: room)
        cell.setRoleIcon(roleIcon?.systemImageName, withAccessibilityLabel: roleIcon?.localizedName)

        cell.avatarView.setStatus(for: participant, inRoom: room)
        cell.setUserStatusMessage(participant.statusMessage, withIcon: participant.statusIcon)

        if (participant.statusMessage ?? "").isEmpty {
            if participant.status == kUserStatusDND {
                cell.setUserStatusMessage(NSLocalizedString("Do not disturb", comment: ""), withIcon: nil)
            } else if participant.status == kUserStatusAway {
                cell.setUserStatusMessage(NSLocalizedString("Away", comment: ""), withIcon: nil)
            }
        }

        if let invitedActorId = participant.invitedActorId, !invitedActorId.isEmpty {
            cell.setUserStatusMessage(invitedActorId, withIcon: nil)
        }

        let contentAlpha: CGFloat = participant.isOffline ? 0.5 : 1
        cell.avatarView.alpha = contentAlpha
        cell.labelTitle.alpha = contentAlpha
        cell.userStatusMessageLabel.alpha = contentAlpha
        cell.roleIconView.alpha = contentAlpha

        if let callIconImageName = participant.callIconImageName, !callIconImageName.isEmpty {
            cell.accessoryView = UIImageView(image: .init(systemName: callIconImageName))
            cell.accessoryView?.tintColor = .secondaryLabel
        } else {
            cell.accessoryView = nil
        }
    }
}
