//
// Copyright (c) 2024 Marcel Müller <marcel-mueller@gmx.de>
//
// Author Marcel Müller <marcel-mueller@gmx.de>
//
// GNU GPL version 3 or any later version
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
import SwiftUI

extension NCUserStatus {

    static func getOnlineIcon() -> some View {
        return Image(systemName: "circle.fill").font(.system(size: 16)).symbolRenderingMode(.monochrome).foregroundStyle(.green)
    }

    static func getAwayIcon() -> some View {
        return Image(systemName: "moon.fill").font(.system(size: 16)).symbolRenderingMode(.monochrome).foregroundStyle(.yellow)
    }

    static func getDoNotDisturbIcon() -> some View {
        if #available(iOS 16.1, *) {
            return Image(systemName: "wrongwaysign.fill").font(.system(size: 16)).symbolRenderingMode(.palette).foregroundStyle(.white, .red)
        }

        return Image(systemName: "minus.circle.fill").font(.system(size: 16)).symbolRenderingMode(.palette).foregroundStyle(.white, .red)
    }

    static func getInvisibleIcon() -> some View {
        return Image(systemName: "circle").font(.system(size: 16, weight: .black)).foregroundColor(.primary)
    }

    static func getUserStatusIcon(userStatus: String) -> any View {
        if userStatus == kUserStatusOnline {
            return getOnlineIcon()
        } else if userStatus == kUserStatusAway {
            return getAwayIcon()
        } else if userStatus == kUserStatusDND {
            return getDoNotDisturbIcon()
        } else if userStatus == kUserStatusInvisible {
            return getInvisibleIcon()
        }

        return Image(systemName: "person.fill.questionmark")
    }
}
