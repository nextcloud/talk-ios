//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import NextcloudKit

struct RoomInfoWebinarSection: View {
    @Binding var room: NCRoom

    private let manualStartTimeText = NSLocalizedString("Manual", comment: "TRANSLATORS this is used when no meeting start time is set and the meeting will be started manually")
    private let startingDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
    private let minimumDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())

    var body: (some View)? {
        guard room.canModerate else { return Body.none }

        return Section(header: Text("Meeting settings")) {
            let isLobbyEnabled = Binding<Bool>(get: {
                self.room.lobbyState == .moderatorsOnly
            }, set: {
                self.room.lobbyState = $0 ? .moderatorsOnly : .allParticipants
            })

            ActionToggle(isOn: isLobbyEnabled, action: { newValue in
                await setLobbyState(withNewState: newValue ? .moderatorsOnly : .allParticipants, withTimer: 0)
            }, label: {
                ImageSublabelView(image: Image("lobby").renderingMode(.template)) {
                    Text("Lobby")
                }
            })

            if isLobbyEnabled.wrappedValue {
                ImageSublabelView(image: Image(systemName: "calendar.badge.clock")) {
                    HStack {
                        Text("Start time")
                        DatePickerTextFieldWrapper(placeholder: self.room.lobbyTimer == 0 ? manualStartTimeText : NCUtils.readableDateTime(fromDate: Date(timeIntervalSince1970: TimeInterval(self.room.lobbyTimer))),
                                                   minimumDate: minimumDate,
                                                   startingDate: startingDate,
                                                   buttons: self.room.lobbyTimer == 0 ? .cancelAndDone : .removeAndDone) { buttonTapped, selectedDate in

                            Task {
                                if buttonTapped == .done, let selectedDate {
                                    await setLobbyState(withNewState: .moderatorsOnly, withTimer: Int(selectedDate.timeIntervalSince1970))
                                } else if buttonTapped == .remove {
                                    await setLobbyState(withNewState: .moderatorsOnly, withTimer: 0)
                                }
                            }
                        }.id(room)
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
                    await setSipState(withNewState: newValue ? .enabled : .disabled)
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
                        await setSipState(withNewState: newValue ? .enabledWithoutPIN : .enabled)
                    }, label: {
                        ImageSublabelView(image: Image(uiImage: UIImage())) {
                            Text("Allow to dial-in without a pin")
                        }
                    })
                }
            }
        }
    }

    func setLobbyState(withNewState newState: NCRoomLobbyState, withTimer timer: Int) async {
        do {
            try await NCAPIController.sharedInstance().setLobbyState(state: newState, withTimer: timer, forRoom: room.token, forAccount: room.account!)
        } catch {
            NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not change lobby state of the conversation", comment: ""), withMessage: nil)
        }

        NCRoomsManager.sharedInstance().updateRoom(room.token, withCompletionBlock: nil)
    }

    func setSipState(withNewState newState: NCRoomSIPState) async {
        do {
            try await NCAPIController.sharedInstance().setSIPState(state: newState, forRoom: room.token, forAccount: room.account!)
        } catch {
            NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not change SIP state of the conversation", comment: ""), withMessage: nil)
        }

        NCRoomsManager.sharedInstance().updateRoom(room.token, withCompletionBlock: nil)
    }
}
