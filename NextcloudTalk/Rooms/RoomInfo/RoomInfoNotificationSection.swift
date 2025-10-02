//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import NextcloudKit

struct RoomInfoNotificationSection: View {
    @Binding var room: NCRoom

    var body: (some View)? {
        guard room.type != .changelog, room.type != .noteToSelf else {
            return Body.none
        }

        return Section(header: Text("Notifications")) {
            if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityNotificationLevels) {
                // TODO: Rework the layout into ActionPicker
                ImageSublabelView(image: Image(systemName: "bell")) {
                    HStack {
                        Text("Chat messages")
                        Spacer()
                        ActionPicker(selection: $room.notificationLevel, action: { newValue in
                            await setNotificationLevel(toLevel: newValue)
                        }, label: {}, content: {
                            Text(verbatim: NCRoom.stringFor(notificationLevel: .always)).tag(NCRoomNotificationLevel.always)
                            Text(verbatim: NCRoom.stringFor(notificationLevel: .mention)).tag(NCRoomNotificationLevel.mention)
                            Text(verbatim: NCRoom.stringFor(notificationLevel: .never)).tag(NCRoomNotificationLevel.never)
                        })
                    }
                }
            }

            if NCDatabaseManager.sharedInstance().roomHasTalkCapability(kCapabilityNotificationCalls, for: room), room.supportsCalling {
                ActionToggle(isOn: $room.notificationCalls, action: { newValue in
                    await setCallNotifications(toEnabled: newValue)
                }, label: {
                    ImageSublabelView(image: Image(systemName: "phone")) {
                        Text("Calls")
                    }
                })
            }

            if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityImportantConversations) {
                ActionToggle(isOn: $room.isImportant, action: { newValue in
                    await setImportantConversation(toEnabled: newValue)
                }, label: {
                    ImageSublabelView(image: Image(systemName: "exclamationmark.bubble")) {
                        Text("Important conversation")
                    } sublabel: {
                        Text("'Do not disturb' user status is ignored for important conversations")
                    }
                })
            }

            if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilitySensitiveConversations) {
                ActionToggle(isOn: $room.isSensitive, action: { newValue in
                    await setSensitiveConversation(toEnabled: newValue)
                }, label: {
                    ImageSublabelView(image: Image(systemName: "lock.shield")) {
                        Text("Sensitive conversation")
                    } sublabel: {
                        Text("Message preview will be disabled in conversation list and notifications")
                    }
                })
            }
        }
    }

    func setNotificationLevel(toLevel newLevel: NCRoomNotificationLevel) async {
        let success = await NCAPIController.sharedInstance().setNotificationLevel(level: newLevel, forRoom: room.token, forAccount: room.account!)
        if !success {
            NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not change notifications setting", comment: ""), withMessage: nil)
        }

        NCRoomsManager.sharedInstance().updateRoom(room.token, withCompletionBlock: nil)
    }

    func setCallNotifications(toEnabled newValue: Bool) async {
        let success = await NCAPIController.sharedInstance().setCallNotificationLevel(enabled: newValue, forRoom: room.token, forAccount: room.account!)
        if !success {
            NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not change call notifications setting", comment: ""), withMessage: nil)
        }

        NCRoomsManager.sharedInstance().updateRoom(room.token, withCompletionBlock: nil)
    }

    func setImportantConversation(toEnabled newValue: Bool) async {
        do {
            let updatedRoom = try await NCAPIController.sharedInstance().setImportantState(enabled: newValue, forRoom: room.token, forAccount: room.account!)
            self.room = updatedRoom!
        } catch {
            NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not change important conversation setting", comment: ""), withMessage: nil)
            NCRoomsManager.sharedInstance().updateRoom(room.token, withCompletionBlock: nil)
        }
    }

    func setSensitiveConversation(toEnabled newValue: Bool) async {
        if let updatedRoom = try? await NCAPIController.sharedInstance().setSensitiveState(enabled: newValue, forRoom: room.token, forAccount: room.account!) {
            self.room = updatedRoom
        } else {
            NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not change sensitive conversation setting", comment: ""), withMessage: nil)
            NCRoomsManager.sharedInstance().updateRoom(room.token, withCompletionBlock: nil)
        }
    }
}
