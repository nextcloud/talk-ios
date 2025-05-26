//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import NextcloudKit

struct RoomInfoNonDestructiveSection: View {
    @Binding var room: NCRoom

    private let archiveConversationText = NSLocalizedString("Archive conversation", comment: "")
    private let unarchiveConversationText = NSLocalizedString("Unarchive conversation", comment: "")

    var body: (some View)? {
        guard NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityArchivedConversationsV2) else {
            return Body.none
        }

        return Section {
            Button(action: archiveConversation) {
                ImageSublabelView(image: Image(systemName: "archivebox")) {
                    Text(room.isArchived ? unarchiveConversationText : archiveConversationText)
                }
            }.foregroundStyle(.primary)
        } footer: {
            if room.isArchived {
                Text("Once a conversation is unarchived, it will be shown by default again.")
            } else {
                Text("Archived conversations are hidden from the conversation list by default. They will only be shown when you open archived conversations list.")
            }
        }
    }

    func archiveConversation() {
        let method = room.isArchived ? NCAPIController.sharedInstance().unarchiveRoom : NCAPIController.sharedInstance().archiveRoom

        method(room.token, room.account!) { success in
            if !success {
                NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not change archived conversation setting", comment: ""), withMessage: nil)
            }

            NCRoomsManager.sharedInstance().updateRoom(room.token, withCompletionBlock: nil)
        }
    }
}
