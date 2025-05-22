//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import NextcloudKit

struct RoomInfoHeaderSection: View {
    let hostingWrapper: HostingControllerWrapper

    @Binding var room: NCRoom
    @Binding var profileInfo: ProfileInfo?

    var body: (some View)? {
        Section {
            Button(action: {
                hostingWrapper.pushViewController(RoomAvatarInfoTableViewController(room: room), animated: true)
            }, label: {
                RoomNameTableViewCellWrapper(room: $room)
                    .frame(height: 78)          // Height set in the XIB file
                    .allowsHitTesting(false)    // Pass touch gestures through to SwiftUIs NavigationLink
            })
            .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 12)) // Don't apply additional padding
            .disabled(!room.canModerate && room.type != .noteToSelf)
        }

        if let description = room.parsedRoomDescription {
            Section {
                // TODO: Use UITextView wrapper to enable data detectors
                Text(description)
                    .textSelection(.enabled)
            }
        }

        if let profileInfo, profileInfo.hasAnyInformation() {
            Section {
                if let firstLine = profileInfo.getFirstProfileLine() {
                    ImageSublabelView(image: Image(systemName: "person")) {
                        Text(firstLine)
                    }
                }

                if let secondLine = profileInfo.getSecondProfileLine() {
                    ImageSublabelView(image: Image(systemName: "building")) {
                        Text(secondLine)
                    }
                }

                if let timezoneOffset = profileInfo.timezoneOffset {
                    ImageSublabelView(image: Image(systemName: "clock")) {
                        let myOffset = TimeZone.current.secondsFromGMT()
                        let resultOffset = timezoneOffset - myOffset
                        let localTime = Date(timeIntervalSince1970: Date().timeIntervalSince1970 + TimeInterval(resultOffset))
                        let timeString = String(format: NSLocalizedString("Local time: %@", comment: ""), NCUtils.getTime(fromDate: localTime))

                        Text(verbatim: timeString)
                    }
                }
            }
        }
    }
}
