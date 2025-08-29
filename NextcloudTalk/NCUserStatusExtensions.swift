//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SwiftUI

extension NCUserStatus {

    static func getOnlineIcon() -> some View {
        return Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).symbolRenderingMode(.monochrome).foregroundStyle(.green)
    }

    static func getAwayIcon() -> some View {
        return Image(systemName: "clock.fill").font(.system(size: 16)).symbolRenderingMode(.monochrome).foregroundStyle(.yellow)
    }

    static func getBusyIcon() -> some View {
        return Image(systemName: "circle.fill").font(.system(size: 16)).symbolRenderingMode(.monochrome).foregroundStyle(.red)
    }

    static func getDoNotDisturbIcon() -> some View {
        return Image(systemName: "minus.circle.fill").font(.system(size: 16)).symbolRenderingMode(.monochrome).foregroundStyle(.red)
    }

    static func getInvisibleIcon() -> some View {
        return Image(systemName: "circle").font(.system(size: 16, weight: .bold)).foregroundColor(.primary)
    }

    static func getUserStatusIcon(userStatus: String) -> any View {
        if userStatus == kUserStatusOnline {
            return getOnlineIcon()
        } else if userStatus == kUserStatusAway {
            return getAwayIcon()
        } else if userStatus == kUserStatusBusy {
            return getBusyIcon()
        } else if userStatus == kUserStatusDND {
            return getDoNotDisturbIcon()
        } else if userStatus == kUserStatusInvisible {
            return getInvisibleIcon()
        }

        return Image(systemName: "person.fill.questionmark")
    }
}
