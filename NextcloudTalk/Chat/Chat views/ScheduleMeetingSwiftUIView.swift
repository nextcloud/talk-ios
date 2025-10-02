//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import SwiftUIIntrospect
@_spi(Advanced) import SwiftUIIntrospect

struct ScheduleMeetingSwiftUIView: View {
    @Environment(\.dismiss) var dismiss
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var start: Date = .now
    @State private var end: Date = .now + 60 * 60
    @State private var calendars: [NCCalendar] = []
    @State private var selectedCalendar: NCCalendar?
    @State private var isCalendarPickerExpanded: Bool = false
    @State private var isSwitchEnabled: Bool = true
    @State private var roomParticipants: [NCRoomParticipant] = []
    @State private var selectedParticipants: [NCRoomParticipant] = []
    @State private var isCreatingMeeting = false

    let account: TalkAccount
    let room: NCRoom

    var onMeetingCreationSuccess: (() -> Void)?

    var areAllParticipantsSelected: Bool {
        selectedParticipants.map { $0.actorId ?? "" }.sorted() == roomParticipants.map { $0.actorId ?? "" }.sorted()
    }

    var canCreateMeeting: Bool {
        if let selectedCalendar = selectedCalendar, !selectedCalendar.calendarUri.isEmpty {
            return true
        }

        return false
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .center) {
                List {
                    Section(header: Text("Title")) {
                        TextField("Title", text: $title)
                    }

                    Section(header: Text("Description")) {
                        TextField("Description", text: $description, axis: .vertical)
                    }

                    Section(header: Text("Schedule", comment: "Noun. 'Schedule' of a meeting")) {
                        DatePicker("From", selection: $start, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        DatePicker("To", selection: $end, in: start.addingTimeInterval(60 * 15)..., displayedComponents: [.date, .hourAndMinute])
                    }
                    .tint(Color(NCAppBranding.themeColor()))

                    Section(header: Text("Calendar")) {
                        DisclosureGroup(
                            selectedCalendar?.displayName ?? "Select an option",
                            isExpanded: $isCalendarPickerExpanded
                        ) {
                            ForEach(calendars, id: \.displayName) { calendar in
                                Button(action: {
                                    selectedCalendar = calendar
                                    isCalendarPickerExpanded = false
                                }) {
                                    Text(calendar.displayName)
                                }
                            }
                        }
                    }

                    Section(
                        header: Text("Attendees"),
                        footer: Text(footerString())
                    ) {
                        Toggle(NSLocalizedString("Invite all users and emails", comment: "Invitation for a meeting"), isOn: $isSwitchEnabled)
                            .tint(Color(NCAppBranding.elementColor()))
                            .onChange(of: isSwitchEnabled) { enabled in
                                if !enabled && areAllParticipantsSelected {
                                    selectedParticipants = []
                                } else if enabled && !areAllParticipantsSelected {
                                    selectedParticipants = roomParticipants
                                }
                            }
                            .onChange(of: selectedParticipants) { _ in
                                isSwitchEnabled = areAllParticipantsSelected
                            }
                            .onAppear {
                                isSwitchEnabled = areAllParticipantsSelected
                            }

                        NavigationLink(destination: SelectParticipantsView(
                            roomParticipants: $roomParticipants,
                            selectedParticipants: $selectedParticipants
                        )) {
                            if areAllParticipantsSelected {
                                Image(systemName: "pencil")
                                Text("Edit attendees")
                            } else {
                                Image(systemName: "person.badge.plus")
                                Text("Add attendees")
                            }
                        }
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitle(Text("Schedule a meeting"), displayMode: .inline)
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

                ToolbarItem(placement: .navigationBarTrailing) {
                    if isCreatingMeeting {
                        ProgressView()
                    } else {
                        Button(action: createMeeting) {
                            Text("Create")
                        }
                        .disabled(!canCreateMeeting)
                    }
                }
            })
        }
        .introspect(.navigationView(style: .stack), on: .iOS(.v15...)) { navController in
            NCAppBranding.styleViewController(navController)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .tint(Color(getTintColor()))
        .onAppear() {
            initStartEndTimes()
            fetchCalendars()
            fetchParticipants()
        }
    }

    private func getTintColor() -> UIColor {
        if #available(iOS 26.0, *) {
            return .label
        } else {
            return NCAppBranding.themeTextColor()
        }
    }

    private func footerString() -> String {
        var localizedText: String

        if self.selectedParticipants.isEmpty {
            return NSLocalizedString("Sending no invitations", comment: "")
        } else if self.selectedParticipants.count == 1 {
            localizedText = String(
                format: NSLocalizedString("%@ will receive an invitation", comment: "Alice will receive an invitation"),
                self.selectedParticipants[0].displayName
            )

        } else if self.selectedParticipants.count == 2 {
            localizedText = String(
                format: NSLocalizedString("%@ and %@ will receive invitations", comment: "Alice and Bob will receive invitations"),
                self.selectedParticipants[0].displayName, self.selectedParticipants[1].displayName
            )

        } else if self.selectedParticipants.count == 3 {
            localizedText = String(
                format: NSLocalizedString("%@, %@ and %@ will receive invitations", comment: "Alice, Bob and Charlie will receive invitations"),
                self.selectedParticipants[0].displayName, self.selectedParticipants[1].displayName, self.selectedParticipants[2].displayName
            )

        } else if self.selectedParticipants.count == 4 {
            localizedText = String(
                format: NSLocalizedString("%@, %@, %@ and 1 other will receive invitations", comment: "Alice, Bob, Charlie and 1 other will receive invitations"),
                self.selectedParticipants[0].displayName, self.selectedParticipants[1].displayName, self.selectedParticipants[2].displayName
            )

        } else {
            let othersCount = self.selectedParticipants.count - 3
            localizedText = String(
                format: NSLocalizedString("%@, %@, %@ and %ld others will receive invitations", comment: "Alice, Bob, Charlie and 3 others will receive invitations"),
                self.selectedParticipants[0].displayName, self.selectedParticipants[1].displayName, self.selectedParticipants[2].displayName, othersCount
            )
        }

        return localizedText
    }

    private func initStartEndTimes() {
        let calendar = Calendar.current
        let now = Date()
        if let nextHour = calendar.date(byAdding: .hour, value: 1, to: now) {
            start = calendar.date(bySettingHour: calendar.component(.hour, from: nextHour),
                                  minute: 0,
                                  second: 0,
                                  of: nextHour) ?? now + (60 * 60)
            end = calendar.date(bySettingHour: calendar.component(.hour, from: nextHour),
                                minute: 15,
                                second: 0,
                                of: nextHour) ?? now + (60 * 60) + (60 * 15)
        }
    }

    private func fetchCalendars() {
        NCAPIController.sharedInstance().getCalendars(forAccount: account) { calendars in
            self.calendars = calendars
            self.selectedCalendar = self.calendars.first
        }
    }

    private func fetchParticipants() {
        Task {
            guard let participants = try? await NCAPIController.sharedInstance().getParticipants(forRoom: room.token, forAccount: account)
            else { return }

            let filteredParticipants = participants.filter { $0.actorId != account.userId }
            self.roomParticipants = filteredParticipants
            self.selectedParticipants = isSwitchEnabled ? filteredParticipants : []
        }
    }

    private func createMeeting() {
        guard let calendarUri = selectedCalendar?.calendarUri, !calendarUri.isEmpty else { return }

        var attendeeIds: [Int]?
        if !areAllParticipantsSelected {
            attendeeIds = selectedParticipants.map(\.attendeeId)
        }

        // Work around for a SwiftUI bug in DatePicker
        // The UI does not allow to pick an end date smaller than (start + 15 min). We can still
        // end up in this situation, if only the start date was modified, but not the end date.
        // Therefore it can only happen if end should be (start + 15 min), so we set it here again
        if start >= end {
            end = start.addingTimeInterval(60 * 15)
        }

        isCreatingMeeting = true
        NCAPIController.sharedInstance().createMeeting(
            account: account,
            token: room.token,
            title: title.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces),
            start: Int(start.timeIntervalSince1970),
            end: Int(end.timeIntervalSince1970),
            calendarUri: calendarUri,
            attendeeIds: attendeeIds
        ) { response in
            self.isCreatingMeeting = false

            guard response == .success else {
                var errorMessage: String

                switch response {
                case .calendarError:
                    errorMessage = NSLocalizedString("Failed to get calendar to schedule a meeting", comment: "")
                case .emailError:
                    errorMessage = NSLocalizedString("Invalid email address", comment: "")
                case .startError:
                    errorMessage = NSLocalizedString("Invalid start date", comment: "")
                case .endError:
                    errorMessage = NSLocalizedString("Invalid end date", comment: "")
                default:
                    errorMessage = NSLocalizedString("An error occurred while creating the meeting", comment: "")
                }

                NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not create meeting", comment: ""), withMessage: errorMessage)
                return
            }

            onMeetingCreationSuccess?()
            NotificationPresenter.shared().present(text: NSLocalizedString("Meeting created", comment: ""), dismissAfterDelay: 5.0, includedStyle: .dark)
            dismiss()
        }
    }
}

struct SelectParticipantsView: View {
    @Binding var roomParticipants: [NCRoomParticipant]
    @Binding var selectedParticipants: [NCRoomParticipant]

    var body: some View {
        List(roomParticipants, id: \.displayName) { participant in
            ParticipantCellView(participant: participant, isSelected: selectedParticipants.contains(participant)) {
                if selectedParticipants.contains(participant) {
                    selectedParticipants.removeAll { $0 == participant }
                } else {
                    selectedParticipants.append(participant)
                }
            }
        }
        .navigationTitle("Meeting attendees")
        .overlay {
            if selectedParticipants.isEmpty {
                Text("No participants found").foregroundStyle(.secondary)
            }
        }
    }
}

struct ParticipantCellView: View {
    let participant: NCRoomParticipant
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack {
            AvatarImageViewWrapper(actorId: Binding.constant(participant.actorId), actorType: Binding.constant(participant.actorType?.rawValue))
                .frame(width: 28, height: 28)
                .clipShape(Capsule())
            Text(participant.displayName)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(NCAppBranding.elementColor()))
            } else {
                Image(systemName: "circle")
                    .foregroundColor(Color(NCAppBranding.placeholderColor()))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}
