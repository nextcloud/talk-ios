//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import SwiftUI
import SwiftUIIntrospect
@_spi(Advanced) import SwiftUIIntrospect

@objc protocol UserStatusViewDelegate: AnyObject {
    func userStatusViewDidDisappear()
}

struct UserStatusSwiftUIView: View {

    @Environment(\.dismiss) var dismiss
    @State var userStatus: NCUserStatus
    @State var absenceStatus: UserAbsence?
    @State var changed: Bool = false

    weak var delegate: UserStatusViewDelegate?

    let absenceSupported = NCDatabaseManager.sharedInstance().serverCapabilities()?.absenceSupported ?? false

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

                    if absenceSupported {
                        Section(header: Text("Absence")) {
                            if let absenceStatus {
                                NavigationLink(destination: {
                                    UserStatusAbsenceSwiftUIView(changed: $changed, absenceStatus: absenceStatus)
                                }, label: {
                                    AbsenceLabelView(absenceStatus: $absenceStatus)
                                })
                            } else {
                                ProgressView().tint(.secondary)
                            }
                        }
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
                                Text("Close")
                                    .foregroundColor(Color(getTintColor()))
                            }
                }
            })
        }
        .introspect(.navigationView(style: .stack), on: .iOS(.v15...)) { navController in
            NCAppBranding.styleViewController(navController)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .tint(Color(getTintColor()))
        .onAppear {
            getUserStatus()
            getAbsenceStatus()
        }
        .onChange(of: changed) { newValue in
            if newValue == true {
                getUserStatus()
                getAbsenceStatus()
                changed = false
            }
        }
        .onDisappear {
            delegate?.userStatusViewDidDisappear()
        }
    }

    private func getTintColor() -> UIColor {
        if #available(iOS 26.0, *) {
            return .label
        } else {
            return NCAppBranding.themeTextColor()
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

    func getAbsenceStatus() {
        guard absenceSupported else { return }

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCAPIController.sharedInstance().getUserAbsence(forAccountId: activeAccount.accountId, forUserId: activeAccount.userId) { absenceData in
            guard let absenceData else {
                absenceStatus = UserAbsence(dictionary: [:])
                return
            }

            absenceStatus = absenceData
        }
    }
}

extension UserStatusSwiftUIView {
    // Move init to extension to keep the memberwise initializer of structs
    init(userStatus: NCUserStatus) {
        _userStatus = State(initialValue: userStatus)
    }
}

/*
struct UserStatusSwiftUIViewPreview: PreviewProvider {
    static var previews: some View {
        let absenceData: [String: Any] = [
            "id": 1,
            "firstDay": "2025-01-01",
            "lastDay": "2025-01-10",
            "status": "I'm away",
            "message": "I'm really away"
        ]

        @State var userStatus = NCUserStatus()
        @State var absence = UserAbsence(dictionary: absenceData)

        userStatus.status = "online"

        return UserStatusSwiftUIView(userStatus: userStatus, absenceStatus: absence)
    }
}
*/

@objc class UserStatusSwiftUIViewFactory: NSObject {

    @objc static func create(userStatus: NCUserStatus, delegate: UserStatusViewDelegate) -> UIViewController {
        var userStatusView = UserStatusSwiftUIView(userStatus: userStatus)
        userStatusView.delegate = delegate
        let hostingController = UIHostingController(rootView: userStatusView)

        return hostingController
    }
}
