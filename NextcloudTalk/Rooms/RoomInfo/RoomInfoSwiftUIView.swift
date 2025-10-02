//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import NextcloudKit

class HostingControllerWrapper {
    // See: https://stackoverflow.com/a/67334873
    weak var controller: UIViewController?

    func pushViewController(_ vc: UIViewController, animated: Bool) {
        controller?.navigationController?.pushViewController(vc, animated: animated)
    }

    func presentViewController(_ vc: UIViewController, animated: Bool) {
        controller?.present(vc, animated: animated)
    }
}

struct RoomInfoSwiftUIView: View {
    let hostingWrapper: HostingControllerWrapper

    @State var room: NCRoom
    @State var showDestructiveActions: Bool = true
    @State var quickLookUrl: URL?
    @State var profileInfo: ProfileInfo?

    var body: some View {
        List {
            RoomInfoHeaderSection(hostingWrapper: hostingWrapper, room: $room, profileInfo: $profileInfo)

            RoomInfoFileSection(hostingWrapper: hostingWrapper, room: $room, quickLookUrl: $quickLookUrl)
            RoomInfoSharedItemsSection(hostingWrapper: hostingWrapper, room: $room)

            RoomInfoNotificationSection(room: $room)
            RoomInfoConversationSettingsSection(hostingWrapper: hostingWrapper, room: $room)

            RoomInfoGuestSection(room: $room)
            RoomInfoWebinarSection(room: $room)
            RoomInfoSIPInfoSection(room: $room)

            RoomInfoParticipantsSection(hostingWrapper: hostingWrapper, room: $room)

            RoomInfoNonDestructiveSection(room: $room)

            if showDestructiveActions {
                RoomInfoDestructiveSection(room: $room)
            }
        }
        .quickLookPreview($quickLookUrl)
        .environment(\.defaultMinListHeaderHeight, 1)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitle(Text("Conversation settings"), displayMode: .inline)
        .navigationBarHidden(false)
        .navigationTitle("")
        .onReceive(NotificationCenter.default.publisher(for: .NCRoomsManagerDidUpdateRoom)) { output in
            if let updatedRoom = output.userInfo?["room"] as? NCRoom, room.token == updatedRoom.token {
                self.room = updatedRoom
            }
        }
        .task {
            NCRoomsManager.sharedInstance().updateRoom(room.token, withCompletionBlock: nil)

            if room.type == .oneToOne {
                // TODO: Should have some caching here
                NCAPIController.sharedInstance().getUserProfile(forUserId: room.name, forAccount: room.account!) { info in
                    guard let info else { return }

                    self.profileInfo = info
                }
            }
        }
    }
}

@objc class RoomInfoUIViewFactory: NSObject {

    @objc static func create(room: NCRoom, showDestructiveActions: Bool) -> UIViewController {
        let wrapper = HostingControllerWrapper()
        let roomInfoView = RoomInfoSwiftUIView(hostingWrapper: wrapper, room: room, showDestructiveActions: showDestructiveActions)
        let hostingController = UIHostingController(rootView: roomInfoView)
        hostingController.title = NSLocalizedString("Conversation settings", comment: "")
        NCAppBranding.styleViewController(hostingController)

        wrapper.controller = hostingController

        return hostingController
    }
}
