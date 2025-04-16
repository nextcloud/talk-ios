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
        selectedParticipants.map { $0.actorId }.sorted() == roomParticipants.map { $0.actorId }.sorted()
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
                        if #available(iOS 16.0, *) {
                            TextField("Description", text: $description, axis: .vertical)
                        } else {
                            // Work around for auto-expanding TextField in iOS < 16
                            ZStack {
                                TextEditor(text: $description)
                                Text(description).opacity(0).padding(.all, 8)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                    }

                    Section(header: Text("Schedule")) {
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
                        Toggle("Invite all users and emails", isOn: $isSwitchEnabled)
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
                            .foregroundColor(Color(NCAppBranding.themeTextColor()))
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
        .onAppear() {
            initStartEndTimes()
            fetchCalendars()
            fetchParticipants()
        }
    }

    private func footerString() -> String {
        var localizedSuffix: String

        if self.selectedParticipants.isEmpty {
            return NSLocalizedString("Sending no invitations", comment: "")

        } else if self.selectedParticipants.count == 1 {
            localizedSuffix = NSLocalizedString("will receive an invitation", comment: "Alice will receive an invitation")

        } else if self.selectedParticipants.count == 2 || self.selectedParticipants.count == 3 {
            localizedSuffix = NSLocalizedString("will receive invitations", comment: "Alice and Bob will receive invitations")

        } else if self.selectedParticipants.count == 4 {
            localizedSuffix = NSLocalizedString("and 1 other will receive invitations", comment: "Alice, Bob, Charlie and 1 other is typing…")

        } else {
            let localizedString = NSLocalizedString("and %ld others will receive invitations", comment: "Alice, Bob, Charlie and 3 others will receive invitations")
            localizedSuffix = String(format: localizedString, self.selectedParticipants.count - 3)
        }

        return getParticipantsString() + " " + localizedSuffix
    }

    private func getParticipantsString() -> String {
        if self.selectedParticipants.count == 1,
           let user1 = self.selectedParticipants[0].displayName {
            // Alice
            return user1

        } else {
            let separator = ", "
            let separatorSpace = " "
            let separatorLast = NSLocalizedString("and", comment: "Alice and Bob")

            if self.selectedParticipants.count == 2,
               let user1 = self.selectedParticipants[0].displayName,
               let user2 = self.selectedParticipants[1].displayName {
                // Alice and Bob
                return user1 + separatorSpace + separatorLast + separatorSpace + user2

            } else if self.selectedParticipants.count == 3,
                      let user1 = self.selectedParticipants[0].displayName,
                      let user2 = self.selectedParticipants[1].displayName,
                      let user3 = self.selectedParticipants[2].displayName {
                // Alice, Bob and Charlie
                return user1 + separator + user2 + separatorSpace + separatorLast + separatorSpace + user3

            } else if let user1 = self.selectedParticipants[0].displayName,
                      let user2 = self.selectedParticipants[1].displayName,
                      let user3 = self.selectedParticipants[2].displayName {

                // Alice, Bob, Charlie
                return user1 + separator + user2 + separator + user3

            } else {
                return NSLocalizedString("Participants", comment: "")
            }
        }
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
        NCAPIController.sharedInstance().getParticipantsFromRoom(room.token, for: account) { participants, _ in
            guard let participants = participants as? [NCRoomParticipant] else { return }
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
    }
}

struct ParticipantCellView: View {
    let participant: NCRoomParticipant
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack {
            AvatarImageViewWrapper(actorId: Binding.constant(participant.actorId), actorType: Binding.constant(participant.actorType))
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
