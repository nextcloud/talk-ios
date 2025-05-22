//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import NextcloudKit

struct RoomInfoSharedItemsSection: View {
    let hostingWrapper: HostingControllerWrapper

    @Binding var room: NCRoom

    var body: (some View)? {
        guard !room.isFederated, NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityRichObjectListMedia) else {
            return Body.none
        }

        return Section(header: Text("Shared items")) {
            Button(action: {
                hostingWrapper.pushViewController(RoomSharedItemsTableViewController(room: room), animated: true)
            }, label: {
                // Add disclosure chevron on button
                NavigationLink(destination: EmptyView(), label: {
                    ImageSublabelView(image: Image(systemName: "photo.on.rectangle.angled")) {
                        Text("Images, files, voice messages…")
                    }
                })
            }).foregroundStyle(.primary)
        }
    }
}
