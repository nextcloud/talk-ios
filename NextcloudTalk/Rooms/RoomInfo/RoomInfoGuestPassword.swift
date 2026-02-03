//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import NextcloudKit

struct RoomInfoGuestPassword: View {
    @Binding var room: NCRoom

    @State private var isSetPasswordRowVisible: Bool = false
    @State private var toggleValue: Bool = false
    @State private var isActionRunning = false

    var body: (some View)? {
        ActionToggle(isOn: $toggleValue, action: { isOn in
            if isOn {
                isSetPasswordRowVisible = true
            } else {
                isSetPasswordRowVisible = false
                if room.hasPassword {
                    setPassword(to: "")
                }
            }
        }, label: {
            ImageSublabelView(image: Image(systemName: "lock")) {
                Text("Password protection")
            }
        })
        .onAppear {
            toggleValue = room.hasPassword
        }
        .onChange(of: room.hasPassword) { newValue in
            toggleValue = newValue
        }
        .disabled(isActionRunning)

        if isSetPasswordRowVisible {
            RoomInfoGuestPasswordSave(
                minLength: NCSettingsController.sharedInstance().passwordPolicyMinLength(),
                isPasswordValidationRequired: !(NCSettingsController.sharedInstance().passwordPolicyValidateAPIEndpoint() ?? "").isEmpty
            ) { password in
                isSetPasswordRowVisible = false
                setPassword(to: password)
            }
        }
    }

    func setPassword(to value: String) {
        isActionRunning = true

        NCAPIController.sharedInstance().setPassword(value, forRoom: room.token, forAccount: room.account!) { error, errorDescription in
            if error != nil {
                NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not change password protection settings", comment: ""), withMessage: errorDescription)
            }

            let message = value.isEmpty ?
            NSLocalizedString("Conversation password has been removed", comment: "") :
            NSLocalizedString("Conversation password has been saved", comment: "")
            NotificationPresenter.shared().present(text: message, dismissAfterDelay: 5.0, includedStyle: .success)
            NCRoomsManager.shared.updateRoom(room.token)
            isActionRunning = false
        }
    }
}
