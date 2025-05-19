//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import NextcloudKit

struct RoomInfoWebinarSection: View {
    @Binding var room: NCRoom

    var body: (some View)? {
        guard room.canModerate else { return Body.none }

        return Section(header: Text("Meeting settings")) {
            let isLobbyEnabled = Binding<Bool>(get: {
                self.room.lobbyState == .moderatorsOnly
            }, set: {
                self.room.lobbyState = $0 ? .moderatorsOnly : .allParticipants
            })

            ActionToggle(isOn: isLobbyEnabled, action: { newValue in
                NCAPIController.sharedInstance().setLobbyState(newValue ? .moderatorsOnly : .allParticipants, withTimer: 0, forRoom: room.token, for: room.account!) { error in
                    if error != nil {
                        NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not change lobby state of the conversation", comment: ""), withMessage: nil)
                    }

                    NCRoomsManager.sharedInstance().updateRoom(room.token, withCompletionBlock: nil)
                }
            }, label: {
                ImageSublabelView(image: Image("lobby").renderingMode(.template)) {
                    Text("Lobby")
                }
            })

            let lobbyTimer = Binding<Date>(get: {
                return Date(timeIntervalSince1970: TimeInterval(self.room.lobbyTimer))
            }, set: {
                self.room.lobbyTimer = Int($0.timeIntervalSince1970)
            })

            if isLobbyEnabled.wrappedValue {
                // FIXME: Allow setting and changing back to manual
                // Keep for now for translation
                Text("Manual", comment: "TRANSLATORS this is used when no meeting start time is set and the meeting will be started manually")

                DatePicker(selection: lobbyTimer, in: Date.now...) {
                    ImageSublabelView(image: Image(systemName: "calendar.badge.clock")) {
                        Text("Start time")
                    }
                }
            }

            if room.canEnableSIP {
                let isSipEnabled = Binding<Bool>(get: {
                    self.room.sipState != .disabled
                }, set: {
                    self.room.sipState = $0 ? .enabled : .disabled
                })

                ActionToggle(isOn: isSipEnabled, action: { newValue in
                    NCAPIController.sharedInstance().setSIPState(newValue ? .enabled : .disabled, forRoom: room.token, for: room.account!) { error in
                        if error != nil {
                            NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not change SIP state of the conversation", comment: ""), withMessage: nil)
                        }

                        NCRoomsManager.sharedInstance().updateRoom(room.token, withCompletionBlock: nil)
                    }
                }, label: {
                    ImageSublabelView(image: Image(systemName: "phone")) {
                        Text("SIP dial-in")
                    }
                })

                if isSipEnabled.wrappedValue, NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilitySIPSupportNoPIN) {
                    let isSipEnabledWithoutPin = Binding<Bool>(get: {
                        self.room.sipState == .enabledWithoutPIN
                    }, set: {
                        self.room.sipState = $0 ? .enabledWithoutPIN : .enabled
                    })

                    ActionToggle(isOn: isSipEnabledWithoutPin, action: { newValue in
                        NCAPIController.sharedInstance().setSIPState(newValue ? .enabledWithoutPIN : .enabled, forRoom: room.token, for: room.account!) { error in
                            if error != nil {
                                NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not change SIP state of the conversation", comment: ""), withMessage: nil)
                            }

                            NCRoomsManager.sharedInstance().updateRoom(room.token, withCompletionBlock: nil)
                        }
                    }, label: {
                        ImageSublabelView(image: Image(uiImage: UIImage())) {
                            Text("Allow to dial-in without a pin")
                        }
                    })
                }
            }
        }
    }
}
