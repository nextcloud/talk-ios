//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import NextcloudKit

struct UserStatusAbsenceSwiftUIView: View {

    @Environment(\.dismiss) var dismiss
    @Binding var changed: Bool
    @State var absenceStatus: UserAbsence

    let replacementSupported = NCDatabaseManager.sharedInstance().serverCapabilities()?.absenceReplacementSupported ?? false

    var body: some View {
        VStack(alignment: .center) {
            List {
                Section(header: Text("Details")) {
                    DatePicker(selection: $absenceStatus.firstDay, displayedComponents: .date) {
                        Text("First day")
                    }

                    DatePicker(selection: $absenceStatus.lastDay, in: absenceStatus.firstDay..., displayedComponents: .date) {
                        Text("Last day (inclusive)")
                    }
                }

                if replacementSupported {
                    Section(header: Text("Replacement (optional)", comment: "Replacement in case of out of office")) {
                        NavigationLink(destination: {
                            UserSelectionSwiftUIView(selectedUserId: $absenceStatus.replacementUserId, selectedUserDisplayName: $absenceStatus.replacementUserDisplayName)
                        }, label: {
                            HStack {
                                if absenceStatus.hasReplacementSet {
                                    AvatarImageViewWrapper(actorId: $absenceStatus.replacementUserId, actorType: Binding.constant("users"))
                                        .frame(width: 28, height: 28)
                                        .clipShape(Capsule())

                                    Text(absenceStatus.replacementName)
                                } else {
                                    Text("Select a replacement", comment: "Replacement in case of out of office")
                                        .foregroundStyle(.primary)
                                }
                            }
                        })

                        if absenceStatus.hasReplacementSet {
                            Button("Reset replacement") {
                                absenceStatus.replacementUserId = nil
                                absenceStatus.replacementUserDisplayName = nil
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }

                Section(header: Text("Short absence status")) {
                    TextField("Status", text: $absenceStatus.status)
                }

                Section(header: Text("Long absence message")) {
                    if #available(iOS 16.0, *) {
                        TextField("Message", text: $absenceStatus.message, axis: .vertical)
                    } else {
                        // Work around for auto-expanding TextField in iOS < 16
                        ZStack {
                            TextEditor(text: $absenceStatus.message)
                            Text(absenceStatus.message).opacity(0).padding(.all, 8)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
            }
            .tint(Color(NCAppBranding.themeColor()))

            ButtonContainerSwiftUI {
                NCButtonSwiftUI(title: NSLocalizedString("Disable absence", comment: ""),
                                action: disableAbsence,
                                style: .tertiary,
                                disabled: Binding.constant(!absenceStatus.isValid))
                NCButtonSwiftUI(title: NSLocalizedString("Save", comment: ""),
                                action: setActiveUserStatus,
                                style: .primary,
                                disabled: Binding.constant(!absenceStatus.isValid))
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitle(Text("Absence"), displayMode: .inline)
        .navigationBarHidden(false)
    }

    func setActiveUserStatus() {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCAPIController.sharedInstance().setUserAbsence(forAccountId: activeAccount.accountId, forUserId: activeAccount.user, withAbsence: self.absenceStatus) { success in
            if success {
                dismiss()
                changed.toggle()
                AppStoreReviewController.recordAction(AppStoreReviewController.updateStatus)
            } else {
                NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not set absence", comment: ""), withMessage: NSLocalizedString("An error occurred while setting absence", comment: ""))
            }
        }
    }

    func disableAbsence() {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCAPIController.sharedInstance().clearUserAbsence(forAccountId: activeAccount.accountId, forUserId: activeAccount.userId) { success in
            if success {
                dismiss()
                changed.toggle()
            } else {
                NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not disable absence", comment: ""), withMessage: NSLocalizedString("An error occurred while disabling absence", comment: ""))
            }
        }
    }
}
