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
import SwiftUIIntrospect

struct UserStatusSwiftUIView: View {

    @Environment(\.dismiss) var dismiss
    @State var userStatus: NCUserStatus
    @State var changed: Bool = false

    init(userStatus: NCUserStatus) {
        _userStatus = State(initialValue: userStatus)
    }

    var body: some View {
        NavigationView {
            VStack {
                Form {
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
                    Section(header: Text("Status message")) {
                        NavigationLink(destination: {
                            UserStatusMessageSwiftUIView(changed: $changed)
                        }, label: {
                            Text(userStatus.readableUserStatusMessage().isEmpty ? NSLocalizedString("What is your status?", comment: "") : userStatus.readableUserStatusMessage() )
                        })
                    }
                }
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
        .introspect(.navigationView(style: .stack), on: .iOS(.v15, .v16, .v17)) { navController in
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = NCAppBranding.themeColor()
            appearance.titleTextAttributes = [.foregroundColor: NCAppBranding.themeTextColor()]
            navController.navigationBar.standardAppearance = appearance
            navController.navigationBar.compactAppearance = appearance
            navController.navigationBar.scrollEdgeAppearance = appearance
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
