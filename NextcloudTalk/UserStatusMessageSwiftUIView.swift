//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import NextcloudKit

struct UserStatusMessageSwiftUIView: View {

    @Environment(\.dismiss) var dismiss
    @Binding var changed: Bool
    @State var showClearAtAlert: Bool = false

    @State private var selectedPredefinedMessageId: String?
    @State private var predefinedStatuses: [NKUserStatus] = []

    @State private var selectedIcon: String = ""
    @State private var selectedMessage: String = ""
    @State private var selectedClearAt: Double = 0
    @State private var selectedClearAtString: String = ""

    @State private var userHasStatusSet: Bool = false

    @State private var isLoading: Bool = true
    @FocusState private var textFieldIsFocused: Bool
    @State private var showErrorAlert = false
    @State private var errorAlertTitle = ""
    @State private var errorAlertMessage = ""

    var body: some View {
        VStack(alignment: .center) {
            if isLoading {
                ProgressView()
                    .tint(.secondary)
            } else {
                List {
                    Section(header: Text(NSLocalizedString("What is your status?", comment: ""))) {
                        HStack(spacing: 10) {
                            SingleEmojiTextFieldWrapper(placeholder: "😀", text: $selectedIcon)
                                .frame(maxWidth: 23)
                                .opacity(selectedIcon.isEmpty ? 0.5 : 1.0)
                                .onChange(of: selectedIcon) { _ in
                                    selectedPredefinedMessageId = nil
                                }
                                .focused($textFieldIsFocused)
                            Divider()
                            TextField(NSLocalizedString("What is your status?", comment: ""), text: $selectedMessage)
                                .onChange(of: selectedMessage) { _ in
                                    selectedPredefinedMessageId = nil
                                }
                                .focused($textFieldIsFocused)
                        }
                    }
                    .tint(.primary)

                    Section {
                        ForEach(predefinedStatuses, id: \.id) { status in
                            Button(action: {
                                selectedPredefinedMessageId = status.id
                                selectedIcon = status.icon ?? ""
                                selectedMessage = status.message ?? ""
                                selectedClearAt = status.clearAt?.timeIntervalSince1970 ?? 0
                                selectedClearAtString = getPredefinedClearStatusText(clearAt: status.clearAt, clearAtTime: status.clearAtTime, clearAtType: status.clearAtType)
                                setClearAt(clearAt: selectedClearAtString)
                            }) {
                                HStack(spacing: 20) {
                                    Text(verbatim: status.icon ?? " ")
                                    VStack(alignment: .leading) {
                                        Text(verbatim: status.message ?? "")
                                            .foregroundColor(.primary)

                                        let displayedString = getPredefinedClearStatusText(clearAt: status.clearAt, clearAtTime: status.clearAtTime, clearAtType: status.clearAtType)
                                        Text(verbatim: displayedString)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                    Section {
                        Button(action: {
                            showClearAtAlert.toggle()
                        }) {
                            VStack(alignment: .leading) {
                                Text(NSLocalizedString("Clear status message after", comment: ""))
                                    .foregroundColor(.primary)
                                Text(selectedClearAtString)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                ButtonContainerSwiftUI {
                    NCButtonSwiftUI(title: NSLocalizedString("Clear status message", comment: ""),
                                    action: clearActiveUserStatus,
                                    style: .tertiary,
                                    disabled: Binding.constant(!userHasStatusSet))
                    NCButtonSwiftUI(title: NSLocalizedString("Set status message", comment: ""),
                                    action: setActiveUserStatus,
                                    style: .primary,
                                    disabled: Binding.constant(selectedMessage.isEmpty && selectedIcon.isEmpty))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitle(Text(NSLocalizedString("Status message", comment: "")), displayMode: .inline)
        .navigationBarHidden(false)
        .onAppear {
            getStatus()
        }
        .confirmationDialog("Clear status message after", isPresented: $showClearAtAlert, titleVisibility: .visible) {
            Button("Don't clear") {
                selectedClearAtString = "Don't clear"
                showClearAtAlert = false
                setClearAt(clearAt: NSLocalizedString("Don't clear", comment: ""))
            }
            Button("30 minutes") {
                selectedClearAtString = "30 minutes"
                showClearAtAlert = false
                setClearAt(clearAt: NSLocalizedString("30 minutes", comment: ""))
            }
            Button("1 hour") {
                selectedClearAtString = "1 hour"
                showClearAtAlert = false
                setClearAt(clearAt: NSLocalizedString("1 hour", comment: ""))
            }
            Button("4 hours") {
                selectedClearAtString = "4 hours"
                showClearAtAlert = false
                setClearAt(clearAt: NSLocalizedString("4 hours", comment: ""))
            }
            Button("Today") {
                selectedClearAtString = "Today"
                showClearAtAlert = false
                setClearAt(clearAt: NSLocalizedString("Today", comment: ""))
            }
            Button("This week") {
                selectedClearAtString = "This week"
                showClearAtAlert = false
                setClearAt(clearAt: NSLocalizedString("This week", comment: ""))
            }
        }
        .tint(.blue)
        .alert(isPresented: $showErrorAlert) {
            Alert(title: Text(errorAlertTitle), message: Text(errorAlertMessage), dismissButton: .cancel())
        }
    }

    func getStatus() {
        isLoading = true
        NCAPIController.sharedInstance().setupNCCommunication(for: .active)
        NextcloudKit.shared.getUserStatus { _, clearAt, icon, message, messageId, _, _, _, _, _, error in
            if error.errorCode == 0 {
                userHasStatusSet = !(icon?.isEmpty ?? true) || !(message?.isEmpty ?? true)
                selectedIcon = icon ?? ""
                selectedMessage = message ?? ""
                selectedPredefinedMessageId = messageId
                selectedClearAt = clearAt?.timeIntervalSince1970 ?? 0
                selectedClearAtString = getPredefinedClearStatusText(clearAt: clearAt, clearAtTime: nil, clearAtType: nil)
            }
        }
        NextcloudKit.shared.getUserStatusPredefinedStatuses { _, userStatuses, _, error in
            if error.errorCode == 0 {
                predefinedStatuses = userStatuses ?? []
                withAnimation {
                    isLoading = false
                }
            }
        }
    }

    func setActiveUserStatus() {
        if let selectedPredefinedMessageId {
            NextcloudKit.shared.setCustomMessagePredefined(messageId: selectedPredefinedMessageId, clearAt: selectedClearAt) { _, error in
                if error.errorCode == 0 {
                    dismiss()
                    changed.toggle()
                    AppStoreReviewController.recordAction(AppStoreReviewController.updateStatus)
                } else {
                    triggerErrorAlert(title: NSLocalizedString("Could not set status message", comment: ""),
                                         message: NSLocalizedString("An error occurred while setting status message", comment: ""))
                }
            }
        } else {
            let statusIcon = selectedIcon.isEmpty ? nil : selectedIcon
            NextcloudKit.shared.setCustomMessageUserDefined(statusIcon: statusIcon, message: selectedMessage, clearAt: selectedClearAt) { _, error in
                if error.errorCode == 0 {
                    dismiss()
                    changed.toggle()
                    AppStoreReviewController.recordAction(AppStoreReviewController.updateStatus)
                } else {
                    triggerErrorAlert(title: NSLocalizedString("Could not set status message", comment: ""), message: NSLocalizedString("An error occurred while setting status message", comment: ""))

                }
            }
        }
    }

    func clearActiveUserStatus() {
        NextcloudKit.shared.clearMessage { _, error in
            if error.errorCode == 0 {
                dismiss()
                changed.toggle()
            } else {
                triggerErrorAlert(title: NSLocalizedString("Could not clear status message", comment: ""), message: NSLocalizedString("An error occurred while clearing status message", comment: ""))
            }
        }
    }

    func triggerErrorAlert(title: String, message: String) {
        errorAlertTitle = title
        errorAlertMessage = message
        showErrorAlert.toggle()
    }

    func getClearAt(_ clearAtString: String) -> Double {
        let now = Date()
        let calendar = Calendar.current
        let gregorian = Calendar(identifier: .gregorian)
        let midnight = calendar.startOfDay(for: now)

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: midnight) else { return 0 }
        guard let startweek = gregorian.date(from: gregorian.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else { return 0 }
        guard let endweek = gregorian.date(byAdding: .day, value: 6, to: startweek) else { return 0 }

        switch clearAtString {
        case NSLocalizedString("Don't clear", comment: ""):
            return 0
        case NSLocalizedString("30 minutes", comment: ""):
            let date = now.addingTimeInterval(1800)
            return date.timeIntervalSince1970
        case NSLocalizedString("1 hour", comment: ""), NSLocalizedString("an hour", comment: ""):
            let date = now.addingTimeInterval(3600)
            return date.timeIntervalSince1970
        case NSLocalizedString("4 hours", comment: ""):
            let date = now.addingTimeInterval(14400)
            return date.timeIntervalSince1970
        case NSLocalizedString("Today", comment: ""):
            return tomorrow.timeIntervalSince1970
        case NSLocalizedString("This week", comment: ""):
            return endweek.timeIntervalSince1970
        default:
            return 0
        }
    }

    func setClearAt(clearAt: String) {
        selectedClearAt = getClearAt(clearAt)
        selectedClearAtString = clearAt
    }

    func getPredefinedClearStatusText(clearAt: NSDate?, clearAtTime: String?, clearAtType: String?) -> String {
        if clearAt != nil {
            let from = Date()
            let to = clearAt! as Date

            let day = Calendar.current.dateComponents([.day], from: from, to: to).day ?? 0
            let hour = Calendar.current.dateComponents([.hour], from: from, to: to).hour ?? 0
            let minute = Calendar.current.dateComponents([.minute], from: from, to: to).minute ?? 0

            if day > 0 {
                if day == 1 { return NSLocalizedString("Today", comment: "") }
                return "\(day) " + NSLocalizedString("days", comment: "")
            }

            if hour > 0 {
                if hour == 1 { return NSLocalizedString("an hour", comment: "") }
                if hour == 4 { return NSLocalizedString("4 hours", comment: "") }
                return "\(hour) " + NSLocalizedString("hours", comment: "")
            }

            if minute > 0 {
                if minute >= 25 && minute <= 30 { return NSLocalizedString("30 minutes", comment: "") }
                if minute > 30 { return NSLocalizedString("an hour", comment: "") }
                return "\(minute) " + NSLocalizedString("minutes", comment: "")
            }
        }

        // Period
        // TODO: Use calendar here...
        if clearAtTime != nil && clearAtType == "period" {
            switch clearAtTime {
            case "14400":
                return NSLocalizedString("4 hours", comment: "")
            case "3600":
                return NSLocalizedString("an hour", comment: "")
            case "1800":
                return NSLocalizedString("30 minutes", comment: "")
            case "900":
                return NSLocalizedString("15 minutes", comment: "")
            default:
                return clearAtTime!
            }
        }

        // End of
        if clearAtTime != nil && clearAtType == "end-of" {
            switch clearAtTime {
            case "day":
                return NSLocalizedString("Today", comment: "")
            case "week":
                return NSLocalizedString("This week", comment: "")
            default:
                return clearAtTime!
            }
        }

        return NSLocalizedString("Don't clear", comment: "")
    }
}
