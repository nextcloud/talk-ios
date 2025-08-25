//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import NextcloudKit

struct UserStatusOptionsSwiftUI: View {
    @Environment(\.dismiss) var dismiss

    @Binding var changed: Bool
    @Binding var userStatus: NCUserStatus

    @State private var options: [DetailedOption] = []
    @State private var isLoading: Bool = true

    var body: some View {
            VStack {
                List(options, id: \.self) { option in
                    Button(action: {
                        setActiveUserStatus(userStatus: option.identifier)
                    }) {
                        HStack(spacing: 15) {
                            AnyView(NCUserStatus.getUserStatusIcon(userStatus: option.identifier))
                                .frame(width: 20)
                            VStack(alignment: .leading) {
                                Text(option.title)
                                    .foregroundColor(.primary)
                                if option.subtitle != nil && !option.subtitle.isEmpty {
                                    Text(option.subtitle)
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
            .navigationBarTitle(Text(NSLocalizedString("Online status", comment: "")), displayMode: .inline)
            .navigationBarHidden(false)
        .onAppear {
            getActiveUserStatus()
            presentUserStatusOptions()
        }
    }

    func setActiveUserStatus(userStatus: String) {
        let activeAccount: TalkAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCAPIController.sharedInstance().setUserStatus(userStatus, for: activeAccount) { error in
            if error == nil {
                getActiveUserStatus()
                dismiss()
                changed.toggle()
                AppStoreReviewController.recordAction(AppStoreReviewController.updateStatus)
            } else {
                NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not set online status", comment: ""), withMessage: NSLocalizedString("An error occurred while setting online status", comment: ""))
            }
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
        onlineOption.title = NCUserStatus.readableUserStatus(fromUserStatus: kUserStatusOnline)

        let awayOption = DetailedOption()
        awayOption.identifier = kUserStatusAway
        awayOption.title = NCUserStatus.readableUserStatus(fromUserStatus: kUserStatusAway)

        let busyOption = DetailedOption()
        busyOption.identifier = kUserStatusBusy
        busyOption.title = NCUserStatus.readableUserStatus(fromUserStatus: kUserStatusBusy)

        let dndOption = DetailedOption()
        dndOption.identifier = kUserStatusDND
        dndOption.title = NCUserStatus.readableUserStatus(fromUserStatus: kUserStatusDND)
        dndOption.subtitle = NSLocalizedString("Mute all notifications", comment: "")

        let invisibleOption = DetailedOption()
        invisibleOption.identifier = kUserStatusInvisible
        invisibleOption.title = NCUserStatus.readableUserStatus(fromUserStatus: kUserStatusInvisible)
        invisibleOption.subtitle = NSLocalizedString("Appear offline", comment: "")

        let activeAccount: TalkAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId)

        options.append(onlineOption)
        options.append(awayOption)
        if let serverCapabilities, serverCapabilities.userStatusSupportsBusy {
            options.append(busyOption)
        }
        options.append(dndOption)
        options.append(invisibleOption)
    }
}
