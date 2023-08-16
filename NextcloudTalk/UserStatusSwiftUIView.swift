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

import UIKit
import SwiftUI

struct UserStatusSwiftUIView: View {

    @Environment(\.dismiss) var dismiss
    @State var userStatus: NCUserStatus
    @State private var isPresentingUserStatusMessageOptions = false
    @State private var isPresentingUserStatusOptions = false
    @State var changed: Bool = false

    init(userStatus: NCUserStatus) {
        UINavigationBar.appearance().largeTitleTextAttributes = [.foregroundColor: NCAppBranding.themeColor()]
        UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: NCAppBranding.themeTextColor()]

        UINavigationBar.appearance().backgroundColor = NCAppBranding.themeColor()
        UINavigationBar.appearance().barTintColor = NCAppBranding.themeColor()

        _userStatus = State(initialValue: userStatus)
    }

    var body: some View {
        NavigationView {
            VStack {
                List {
                    Section(header: Text("Online status")) {
                        NavigationLink(destination: {
                            UserStatusOptionsSwiftUI(changed: $changed, userStatus: $userStatus)
                        }, label: {
                            HStack(spacing: 10) {
                                Image(userStatus.userStatusImageName(ofSize: 24))
                                    .renderingMode(.original)
                                Text(userStatus.readableUserStatus())
                            }
                        })
                    }
                    Section {
                        NavigationLink(destination: {
                            UserStatusMessageSwiftUIView(changed: $changed)
                        }, label: {
                            Text(userStatus.readableUserStatusMessage().isEmpty ? NSLocalizedString("What is your status?", comment: "") : userStatus.readableUserStatusMessage() )
                        })
                    } header: {
                        HStack {
                            Text("Status message")
                        }
                    }
                }
                .accentColor(.clear)
            }
            .navigationBarTitle(Text(NSLocalizedString("Status", comment: "")), displayMode: .inline)
            .navigationBarHidden(false)
            .toolbar(content: {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                                dismiss()
                            }) {
                                Text("Cancel")
                                    .foregroundColor(Color(NCAppBranding.themeTextColor()))
                            }
                }
            })
        }
        .tint(Color(NCAppBranding.themeTextColor()))
        .onAppear {
            getUserStatus()
        }
        .onChange(of: changed) { newValue in
            if newValue == true {
                getUserStatus()
                changed = false
            }
        }
    }

    func getUserStatus() {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCAPIController.sharedInstance().getUserStatus(for: activeAccount) { [self] userStatusDict, error in
            if error == nil && userStatusDict != nil {
                userStatus = NCUserStatus(dictionary: userStatusDict!)
            }
        }
    }
}

class UserStatusOptions: ObservableObject {
    @Published var options: [DetailedOption] = []

    init(userStatus: NCUserStatus?) {
        let statusOptions: [(status: String, imageName: String, subtitle: String?)] = [
            (kUserStatusOnline, "online_image_name", nil),
            (kUserStatusAway, "away_image_name", nil),
            (kUserStatusDND, "dnd_image_name", NSLocalizedString("Mute all notifications", comment: "")),
            (kUserStatusInvisible, "invisible_image_name", NSLocalizedString("Appear offline", comment: ""))
        ]

        self.options = statusOptions.map { status, imageName, subtitle in
            let option = DetailedOption()
            option.identifier = status
            option.image = UIImage(named: imageName)?.withRenderingMode(.alwaysOriginal)
            option.title = NCUserStatus.readableUserStatus(fromUserStatus: status)
            option.subtitle = subtitle
            if let userStatus = userStatus {
                option.selected = userStatus.status == status
            }
            return option
        }
    }
}

/*
struct UserStatusSwiftUIView_Previews: PreviewProvider {
    static var previews: some View {
        UserStatusSwiftUIView()
    }
}*/
