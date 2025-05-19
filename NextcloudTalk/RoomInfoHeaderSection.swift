//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import NextcloudKit

struct RoomInfoHeaderSection: View {
    let hostingWrapper: HostingControllerWrapper

    @Binding var room: NCRoom

    var body: (some View)? {
        Section {
            Button(action: {
                hostingWrapper.pushViewController(RoomAvatarInfoTableViewController(room: room), animated: true)
            }, label: {
                RoomNameTableViewCellWrapper(room: $room)
                    .frame(height: 78)          // Height set in the XIB file
                    .allowsHitTesting(false)    // Pass touch gestures through to SwiftUIs NavigationLink
            })
            .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 12)) // Don't apply additional padding
            .disabled(!room.canModerate && room.type != .noteToSelf)
        }

        if let description = room.parsedRoomDescription {
            Section {
                // TODO: Use UITextView wrapper to enable data detectors
                Text(description)
                    .textSelection(.enabled)
            }
        }
    }
}
