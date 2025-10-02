//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import NextcloudKit

struct RoomInfoGuestSection: View {
    @Binding var room: NCRoom

    @State var passwordDialogShown: Bool = false
    @State var password: String = ""

    var body: (some View)? {
        guard room.canModerate else { return Body.none }

        return Section(header: Text("Guests access")) {
            let isPublic = Binding<Bool>(get: {
                self.room.type == .public
            }, set: {
                self.room.type = $0 ? .public : .group
            })

            ActionToggle(isOn: isPublic, action: { makePublic in
                setPublicPrivateState(to: makePublic)
            }, label: {
                ImageSublabelView(image: Image("link").renderingMode(.template)) {
                    Text("Allow guests to join this conversation via link")
                }
            })

            if isPublic.wrappedValue {
                RoomInfoGuestPassword(room: $room)

                if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilitySIPSupport) {
                    Button(action: resendInvitations) {
                        ImageSublabelView(image: Image(systemName: "envelope")) {
                            Text("Resend invitations")
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    func setPublicPrivateState(to makePublic: Bool) {
        let method = makePublic ? NCAPIController.sharedInstance().makeRoomPublic : NCAPIController.sharedInstance().makeRoomPrivate

        method(room.token, room.account!) { error in
            if error != nil {
                NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not change sharing permissions of the conversation", comment: ""), withMessage: nil)
            } else if makePublic {
                NCUserInterfaceController.sharedInstance().presentShareLinkDialog(for: room, inViewContoller: nil, for: nil)
            }

            NCRoomsManager.sharedInstance().updateRoom(room.token, withCompletionBlock: nil)
        }
    }

    func resendInvitations() {
        NCAPIController.sharedInstance().resendInvitation(toParticipant: nil, inRoom: room.token, for: room.account!) { error in
            if error == nil {
                NotificationPresenter.shared().present(text: NSLocalizedString("Invitations resent", comment: ""), dismissAfterDelay: 5.0, includedStyle: .success)
                NCRoomsManager.sharedInstance().updateRoom(room.token, withCompletionBlock: nil)

                return
            }

            NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not resend email invitations", comment: ""), withMessage: nil)
        }
    }
}
