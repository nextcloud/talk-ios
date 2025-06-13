//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import NextcloudKit

struct RoomInfoConversationSettingsSection: View {
    let hostingWrapper: HostingControllerWrapper

    @Binding var room: NCRoom

    var body: (some View)? {
        Section(header: Text("Conversation settings")) {
            if room.supportsMessageExpirationModeration {
                ActionPicker(selection: $room.messageExpiration, action: { newValue in
                    await setMessageExpiration(to: newValue)
                }, label: {
                    ImageSublabelView(image: Image(systemName: "timer")) {
                        Text("Message expiration")
                    }
                }, content: {
                    Text(verbatim: NCRoom.stringFor(messageExpiration: .expirationOff)).tag(NCMessageExpiration.expirationOff)
                    Text(verbatim: NCRoom.stringFor(messageExpiration: .expiration4Weeks)).tag(NCMessageExpiration.expiration4Weeks)
                    Text(verbatim: NCRoom.stringFor(messageExpiration: .expiration1Week)).tag(NCMessageExpiration.expiration1Week)
                    Text(verbatim: NCRoom.stringFor(messageExpiration: .expiration1Day)).tag(NCMessageExpiration.expiration1Day)
                    Text(verbatim: NCRoom.stringFor(messageExpiration: .expiration8Hours)).tag(NCMessageExpiration.expiration8Hours)
                    Text(verbatim: NCRoom.stringFor(messageExpiration: .expiration1Hour)).tag(NCMessageExpiration.expiration1Hour)

                    // Fallback in case a value was set, that is not a default value
                    if NCRoom.stringFor(messageExpiration: room.messageExpiration).isEmpty {
                        Button(action: {}, label: {
                            Text("Custom", comment: "Custom message expiration")
                            Text(verbatim: "\(room.messageExpiration.rawValue)s")
                        }).tag(room.messageExpiration)
                    }
                })
            }

            if room.supportsBanningModeration {
                Button(action: {
                    hostingWrapper.pushViewController(BannedActorTableViewController(room: room), animated: true)
                }, label: {
                    // Add disclosure chevron on button
                    NavigationLink(destination: EmptyView(), label: {
                        ImageSublabelView(image: Image(systemName: "person.badge.minus")) {
                            Text("Banned users and guests")
                        }
                    })
                }).foregroundStyle(.primary)
            }

            if room.canModerate {
                if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityListableRooms) {
                    let listable = Binding<Bool>(get: {
                        self.room.listable != .participantsOnly
                    }, set: {
                        self.room.listable = $0 ? .regularUsersOnly : .participantsOnly
                    })

                    ActionToggle(isOn: listable, action: { newValue in
                        await setListableScope(to: newValue ? .regularUsersOnly : .participantsOnly)
                    }, label: {
                        ImageSublabelView(image: Image(systemName: "list.bullet")) {
                            Text("Open conversation to registered users")
                        }
                    })

                    if listable.wrappedValue, NCSettingsController.sharedInstance().isGuestsAppEnabled() {
                        let listableEveryone = Binding<Bool>(get: {
                            self.room.listable == .everyone
                        }, set: {
                            self.room.listable = $0 ? .everyone : .regularUsersOnly
                        })

                        ActionToggle(isOn: listableEveryone, action: { newValue in
                            await setListableScope(to: newValue ? .everyone : .regularUsersOnly)
                        }, label: {
                            ImageSublabelView(image: Image(uiImage: UIImage())) {
                                Text("Also open to guest app users")
                            }
                        })
                    }
                }

                if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityMentionPermissions) {
                    let mentionPermission = Binding<Bool>(get: {
                        self.room.mentionPermissions == .everyone
                    }, set: {
                        self.room.mentionPermissions = $0 ? .everyone : .moderatorsOnly
                    })

                    ActionToggle(isOn: mentionPermission, action: { newValue in
                        setMentionPermissions(to: newValue ? .everyone : .moderatorsOnly)
                    }, label: {
                        ImageSublabelView(image: Image(systemName: "at.circle")) {
                            Text("Allow participants to mention @all", comment: "'@all' should not be translated")
                        }
                    })
                }

                if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityReadOnlyRooms) {
                    let readOnly = Binding<Bool>(get: {
                        self.room.readOnlyState == .readOnly
                    }, set: {
                        self.room.readOnlyState = $0 ? .readOnly : .readWrite
                    })

                    ActionToggle(isOn: readOnly, action: { newValue in
                        await setReadOnlyState(to: newValue ? .readOnly : .readWrite)
                    }, label: {
                        ImageSublabelView(image: Image(systemName: "lock.square")) {
                            Text("Lock conversation")
                        }
                    })
                }
            }

            if room.type != .changelog, room.type != .noteToSelf {
                Button(action: {
                    NCUserInterfaceController.sharedInstance().presentShareLinkDialog(for: room, inViewContoller: nil, for: nil)
                }, label: {
                    ImageSublabelView(image: Image(systemName: "square.and.arrow.up")) {
                        Text("Share link")
                    }
                }).foregroundStyle(.primary)
            }
        }
    }

    func setMessageExpiration(to newValue: NCMessageExpiration) async {
        do {
            try await NCAPIController.sharedInstance().setMessageExpiration(messageExpiration: newValue, forRoom: room.token, forAccount: room.account!)
        } catch {
            NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not set message expiration time", comment: ""), withMessage: nil)
        }

        NCRoomsManager.sharedInstance().updateRoom(room.token, withCompletionBlock: nil)
    }

    func setListableScope(to newScope: NCRoomListableScope) async {
        do {
            try await NCAPIController.sharedInstance().setListableScope(scope: newScope, forRoom: room.token, forAccount: room.account!)
        } catch {
            NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not change listable scope of the conversation", comment: ""), withMessage: nil)
        }

        NCRoomsManager.sharedInstance().updateRoom(room.token, withCompletionBlock: nil)
    }

    func setMentionPermissions(to newPermission: NCRoomMentionPermissions) {
        NCAPIController.sharedInstance().setMentionPermissions(newPermission, forRoom: room.token, forAccount: room.account!) { error in
            if error != nil {
                NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not change mention permissions of the conversation", comment: ""), withMessage: nil)
            }

            NCRoomsManager.sharedInstance().updateRoom(room.token, withCompletionBlock: nil)
        }
    }

    func setReadOnlyState(to newState: NCRoomReadOnlyState) async {
        do {
            try await NCAPIController.sharedInstance().setReadOnlyState(state: newState, forRoom: room.token, forAccount: room.account!)
        } catch {
            NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not change read-only state of the conversation", comment: ""), withMessage: nil)
        }

        NCRoomsManager.sharedInstance().updateRoom(room.token, withCompletionBlock: nil)
    }
}
