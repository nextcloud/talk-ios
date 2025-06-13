//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import NextcloudKit

struct RoomInfoSIPInfoSection: View {
    @Binding var room: NCRoom

    var body: (some View)? {
        guard room.sipState != .disabled else {
            return Body.none
        }

        return Section(header: Text("SIP dial-in")) {
            // TODO: SwiftUI Text does not support data detectors?
            let signalingConfig = NCSettingsController.sharedInstance().signalingConfigurations.object(forKey: room.account!.accountId) as? SignalingSettings
            Text(signalingConfig?.sipDialinInfo ?? "")

            HStack {
                Text("Meeting ID")
                Spacer()
                Text(verbatim: room.token).foregroundStyle(.secondary)
            }

            HStack {
                Text("Your PIN")
                Spacer()
                Text(verbatim: room.attendeePin).foregroundStyle(.secondary)
            }
        }
    }
}
