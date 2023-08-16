//
// Copyright (c) 2023 Lukas Lauerer <lukas.lauerer@gmx.net>
//
// Author Lukas Lauerer <lukas.lauerer@gmx.net>
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

import SwiftUI
import NextcloudKit

struct UserStatusOptionsSwiftUI: View {
    @Environment(\.dismiss) var dismiss

    @Binding var changed: Bool
    @Binding var userStatus: NCUserStatus

    @State private var options: [DetailedOption] = []
    @State private var isLoading: Bool = true

    init(changed: Binding<Bool>, userStatus: Binding<NCUserStatus>) {
        _changed = changed
        _userStatus = userStatus
    }

    var body: some View {
            VStack {
                List(options, id: \.self) { option in
                    Button(action: {
                        setActiveUserStatus(userStatus: option.identifier)
                    }) {
                        HStack(spacing: 15) {
                            Image(uiImage: option.image)
                            VStack(alignment: .leading) {
                                Text(option.title)
                                    .font(.system(size: 18))
                                    .foregroundColor(.primary)
                                if option.subtitle != nil && !option.subtitle.isEmpty {
                                    Text(option.subtitle)
                                        .font(.system(size: 16))
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if userStatus.status == option.identifier {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(Color(NCAppBranding.themeColor()))
                            }
                        }
                    }
                }
            }
            .navigationBarTitle(Text(NSLocalizedString("Online Status", comment: "")), displayMode: .inline)
            .navigationBarHidden(false)
        .onAppear {
            getActiveUserStatus()
            presentUserStatusOptions()
        }
    }

    func setActiveUserStatus(userStatus: String) {
        let activeAcoount: TalkAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCAPIController.sharedInstance().setUserStatus(userStatus, for: activeAcoount) { _ in
            getActiveUserStatus()
            dismiss()
            changed.toggle()
        }
    }

    func getActiveUserStatus() {
        let activeAccount: TalkAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCAPIController.sharedInstance().getUserStatus(for: activeAccount) { [self] userStatusDict, error in
            if error == nil && userStatusDict != nil {
                userStatus = NCUserStatus(dictionary: userStatusDict!)
            }
        }
    }

    func presentUserStatusOptions() {
        let onlineOption = DetailedOption()
        onlineOption.identifier = kUserStatusOnline
        onlineOption.image = UIImage(named: NCUserStatus.userStatusImageName(forStatus: kUserStatusOnline, ofSize: 24))?.withRenderingMode(.alwaysOriginal)
        onlineOption.title = NCUserStatus.readableUserStatus(fromUserStatus: kUserStatusOnline)

        let awayOption = DetailedOption()
        awayOption.identifier = kUserStatusAway
        awayOption.image = UIImage(named: NCUserStatus.userStatusImageName(forStatus: kUserStatusAway, ofSize: 24))?.withRenderingMode(.alwaysOriginal)
        awayOption.title = NCUserStatus.readableUserStatus(fromUserStatus: kUserStatusAway)

        let dndOption = DetailedOption()
        dndOption.identifier = kUserStatusDND
        dndOption.image = UIImage(named: NCUserStatus.userStatusImageName(forStatus: kUserStatusDND, ofSize: 24))?.withRenderingMode(.alwaysOriginal)
        dndOption.title = NCUserStatus.readableUserStatus(fromUserStatus: kUserStatusDND)
        dndOption.subtitle = NSLocalizedString("Mute all notifications", comment: "")

        let invisibleOption = DetailedOption()
        invisibleOption.identifier = kUserStatusInvisible
        invisibleOption.image = UIImage(named: NCUserStatus.userStatusImageName(forStatus: kUserStatusInvisible, ofSize: 24))?.withRenderingMode(.alwaysOriginal)
        invisibleOption.title = NCUserStatus.readableUserStatus(fromUserStatus: kUserStatusInvisible)
        invisibleOption.subtitle = NSLocalizedString("Appear offline", comment: "")

        options.append(onlineOption)
        options.append(awayOption)
        options.append(dndOption)
        options.append(invisibleOption)
    }
}
/*
struct UserStatusOptionsSwiftUI_Previews: PreviewProvider {
    static var previews: some View {
        UserStatusOptionsSwiftUI()
    }
}
*/
