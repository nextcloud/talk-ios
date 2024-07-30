//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import SwiftUI
import SwiftUIIntrospect
@_spi(Advanced) import SwiftUIIntrospect

protocol UserStatusViewDelegate: AnyObject {
    func userStatusViewDidDisappear()
}

struct UserStatusSwiftUIView: View {

    @Environment(\.dismiss) var dismiss
    @State var userStatus: NCUserStatus
    @State var changed: Bool = false

    init(userStatus: NCUserStatus) {
        _userStatus = State(initialValue: userStatus)
    }

    weak var delegate: UserStatusViewDelegate?

    var body: some View {
        NavigationView {
            VStack {
                Form {
                    Section(header: Text("Online status")) {
                        NavigationLink(destination: {
                            UserStatusOptionsSwiftUI(changed: $changed, userStatus: $userStatus)
                        }, label: {
                            HStack(spacing: 10) {
                                AnyView(NCUserStatus.getUserStatusIcon(userStatus: userStatus.status))
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
        .introspect(.navigationView(style: .stack), on: .iOS(.v15...)) { navController in
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = NCAppBranding.themeColor()
            appearance.titleTextAttributes = [.foregroundColor: NCAppBranding.themeTextColor()]
            navController.navigationBar.tintColor = NCAppBranding.themeTextColor()
            navController.navigationBar.standardAppearance = appearance
            navController.navigationBar.compactAppearance = appearance
            navController.navigationBar.scrollEdgeAppearance = appearance
        }
        .navigationViewStyle(StackNavigationViewStyle())
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
        .onDisappear {
            delegate?.userStatusViewDidDisappear()
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

@objc class UserStatusSwiftUIViewFactory: NSObject {

    @objc static func create(userStatus: NCUserStatus) -> UIViewController {
        let userStatusView = UserStatusSwiftUIView(userStatus: userStatus)
        let hostingController = UIHostingController(rootView: userStatusView)

        return hostingController
    }
}
