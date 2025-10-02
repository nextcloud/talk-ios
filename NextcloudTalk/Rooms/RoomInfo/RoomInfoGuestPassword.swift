//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import NextcloudKit

struct RoomInfoGuestPassword: View {
    @Binding var room: NCRoom

    @State private var setPasswordDialogShown: Bool = false
    @State private var changePasswordDialogShown: Bool = false
    @State private var password: String = ""
    @State private var isActionRunning = false

    var trimmedPassword: String {
        return password.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let changePasswordText = NSLocalizedString("Change password", comment: "")
    private let setPasswordText = NSLocalizedString("Set password", comment: "")

    var body: (some View)? {
        Button(action: {
            if room.hasPassword {
                changePasswordDialogShown = true
            } else {
                setPasswordDialogShown = true
            }
        }, label: {
            ImageSublabelView(image: Image(systemName: room.hasPassword ? "lock" : "lock.open")) {
                Text(room.hasPassword ? changePasswordText : setPasswordText)
            }
        })
        .foregroundStyle(.primary)
        .alert(NSLocalizedString("Set password:", comment: ""), isPresented: $setPasswordDialogShown) {
            SecureField(NSLocalizedString("Password", comment: ""), text: $password)

            Button(action: {
                setPassword(to: trimmedPassword)
            }, label: {
                Text("OK")
            })
            .disabled(trimmedPassword.isEmpty)

            Button("Cancel", role: .cancel) {}
        }
        .alert(NSLocalizedString("Set new password:", comment: ""), isPresented: $changePasswordDialogShown) {
            SecureField(NSLocalizedString("Password", comment: ""), text: $password)

            Button(action: {
                setPassword(to: trimmedPassword)
            }, label: {
                Text(changePasswordText)
            })
            .disabled(trimmedPassword.isEmpty)

            Button(role: .destructive, action: {
                setPassword(to: "")
            }, label: {
                Text("Remove password")
            })

            Button("Cancel", role: .cancel) {}
        }
        .disabled(isActionRunning)
    }

    func setPassword(to value: String) {
        isActionRunning = true

        NCAPIController.sharedInstance().setPassword(value, forRoom: room.token, forAccount: room.account!) { error, errorDescription in
            if error != nil {
                NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not change password protection settings", comment: ""), withMessage: errorDescription)
            }

            NCRoomsManager.sharedInstance().updateRoom(room.token, withCompletionBlock: nil)
            isActionRunning = false
        }
    }
}
