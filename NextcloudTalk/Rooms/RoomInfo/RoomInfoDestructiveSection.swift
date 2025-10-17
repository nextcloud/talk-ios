//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import NextcloudKit

struct RoomInfoDestructiveSection: View {
    @Binding var room: NCRoom

    @State private var showLeaveConfirmation = false
    @State private var showClearConfirmation = false

    var body: (some View)? {
        guard room.canLeaveConversation || room.canDeleteConversation else {
            return Body.none
        }

        return Section {
            if room.canLeaveConversation {
                Button(role: .destructive, action: {
                    self.showLeaveConfirmation = true
                }, label: {
                    ImageSublabelView(image: Image(systemName: "arrow.right.square")) {
                        Text("Leave conversation")
                    }
                })
                .alert(NSLocalizedString("Leave conversation", comment: ""), isPresented: $showLeaveConfirmation, actions: {
                    Button(role: .destructive, action: {
                        Task {
                            await leaveRoom()
                        }
                    }, label: {
                        Text("Leave")
                    })

                    Button("Cancel", role: .cancel) {}
                }, message: {
                    Text("Once a conversation is left, to rejoin a closed conversation, an invite is needed. An open conversation can be rejoined at any time.")
                })
            }

            if room.canDeleteConversation {
                if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityClearHistory) {
                    Button(role: .destructive, action: {
                        showClearConfirmation = true
                    }, label: {
                        ImageSublabelView(image: Image(systemName: "eraser")) {
                            Text("Delete all messages")
                        }
                    })
                    .alert(NSLocalizedString("Delete all messages", comment: ""), isPresented: $showClearConfirmation, actions: {
                        Button(role: .destructive, action: {
                            clearHistory()
                        }, label: {
                            Text("Delete all", comment: "Short version for confirmation button. Complete text is 'Delete all messages'.")
                        })

                        Button("Cancel", role: .cancel) {}
                    }, message: {
                        Text("Do you really want to delete all messages in this conversation?")
                    })
                }

                Button(role: .destructive, action: deleteRoomWithConfirmation) {
                    ImageSublabelView(image: Image(systemName: "trash")) {
                        Text("Delete conversation")
                    }
                }
            }
        }
    }

    func leaveRoom() async {
        do {
            try await NCAPIController.sharedInstance().removeSelf(fromRoom: room.token, forAccount: room.account!)

            NCRoomsManager.sharedInstance().chatViewController?.leaveChat()
            NCUserInterfaceController.sharedInstance().presentConversationsList()
            NCRoomsManager.sharedInstance().updateRoomsUpdatingUserStatus(false, onlyLastModified: false)
        } catch {
            if let error = error as? OcsError, error.responseStatusCode == 400 {
                NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("You need to promote a new moderator before you can leave this conversation", comment: ""), withMessage: nil)
            } else {
                NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not leave conversation", comment: ""), withMessage: nil)
            }
        }
    }

    func clearHistory() {
        NCAPIController.sharedInstance().clearChatHistory(inRoom: room.token, for: room.account!) { _, error, _ in
            if let error {
                print("Error clearing chat history: \(error.localizedDescription)")
                NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not clear chat history", comment: ""), withMessage: nil)
            } else {
                print("Chat history cleared.")
                NotificationPresenter.shared().present(text: NSLocalizedString("All messages were deleted", comment: ""), dismissAfterDelay: 5.0, includedStyle: .success)
            }
        }
    }

    func deleteRoomWithConfirmation() {
        NCRoomsManager.sharedInstance().deleteRoom(withConfirmation: self.room, withStartedBlock: nil) { success in
            if !success {
                NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not delete conversation", comment: ""), withMessage: nil)
            }
        }
    }
}
