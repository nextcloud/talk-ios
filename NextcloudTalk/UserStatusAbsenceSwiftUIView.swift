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
                            Button {
                                absenceStatus.replacementUserId = nil
                                absenceStatus.replacementUserDisplayName = nil
                            } label: {
                                Text("Reset replacement", comment: "Replacement in case of out of office")
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }

                Section(header: Text("Short absence status")) {
                    TextField("Status", text: $absenceStatus.status)
                }

                Section(header: Text("Long absence message")) {
                    TextField("Message", text: $absenceStatus.message, axis: .vertical)
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
        // Work around for a SwiftUI bug in DatePicker
        // The UI does not allow to pick an end date smaller than start. We can still
        // end up in this situation, if only the start date was modified, but not the end date.
        // Therefore it can only happen if end should be equal to start, so we set it here again
        if self.absenceStatus.firstDay >= self.absenceStatus.lastDay {
            self.absenceStatus.lastDay = self.absenceStatus.firstDay
        }

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCAPIController.sharedInstance().setUserAbsence(forAccountId: activeAccount.accountId, forUserId: activeAccount.user, withAbsence: self.absenceStatus) { response in
            guard response == .success else {
                var errorMessage: String

                switch response {
                case .firstDayError:
                    errorMessage = NSLocalizedString("Invalid date range", comment: "")
                case .statusLengthError:
                    errorMessage = NSLocalizedString("Short absence status is too long", comment: "")
                default:
                    errorMessage = NSLocalizedString("An error occurred while setting absence", comment: "")
                }

                NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not set absence", comment: ""), withMessage: errorMessage)
                return
            }

            dismiss()
            changed.toggle()
            AppStoreReviewController.recordAction(AppStoreReviewController.updateStatus)
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
