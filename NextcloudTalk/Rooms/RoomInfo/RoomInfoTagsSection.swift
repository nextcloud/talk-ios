//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct RoomInfoTagsSection: View {
    let hostingWrapper: HostingControllerWrapper
    @Binding var room: NCRoom

    var body: (some View)? {
        guard NCDatabaseManager.sharedInstance().serverHasTalkCapability(.conversationTags, forAccountId: room.accountId),
              room.type != .changelog, room.type != .noteToSelf
        else {
            return Body.none
        }

        return Section {
            Button(action: {
                hostingWrapper.presentViewController(RoomTagsAssignmentView.viewController(for: room, withAccount: room.account!), animated: true)
            }, label: {
                ImageSublabelView(image: Image(systemName: "tag")) {
                    HStack {
                        Text("Tags")
                        Spacer()
                        Text(assignedTagNames())
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            })
            .foregroundColor(.primary)
        }
    }

    private func assignedTagNames() -> String {
        let tags = NCDatabaseManager.sharedInstance().conversationTags(forAccountId: room.accountId)
        let assignedIds = room.tagIdList

        return tags.filter { assignedIds.contains($0.tagId) }.map { $0.name }.joined(separator: ", ")
    }
}
