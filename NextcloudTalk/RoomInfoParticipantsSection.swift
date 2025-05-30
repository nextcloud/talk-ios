//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import NextcloudKit

struct RoomInfoParticipantsSection: View {
    private class AddParticipantCoordinator: NSObject, AddParticipantsTableViewControllerDelegate {
        var parent: RoomInfoParticipantsSection

        init(parent: RoomInfoParticipantsSection) {
            self.parent = parent
        }

        func addParticipantsTableViewControllerDidFinish(_ viewController: AddParticipantsTableViewController!) {
            parent.getParticipants()
        }
    }

    let hostingWrapper: HostingControllerWrapper

    @Binding var room: NCRoom

    @State private var participants: [NCRoomParticipant]?
    @State private var coordinator: AddParticipantCoordinator?

    @State private var banConfirmationShown: Bool = false
    @State private var isBanActionRunning = false
    @State private var participantToBan: NCRoomParticipant?
    @State private var internalNote: String = ""

    var trimmedInternalNote: String {
        return internalNote.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var participantCountText: String {
        return participants == nil ? "" : String.localizedStringWithFormat(NSLocalizedString("%ld participants", comment: ""), participants?.count ?? 0)
    }

    var body: (some View)? {
        if room.canAddParticipants {
            Section(participantCountText) {
                Button(action: addParticipants) {
                    if room.type == .oneToOne {
                        ImageSublabelView(image: Image(systemName: "person.badge.plus")) {
                            Text("Add participants")
                        } sublabel: {
                            Text("Start a new group conversation")
                        }
                    } else {
                        ImageSublabelView(image: Image(systemName: "person.badge.plus")) {
                            Text("Add participants")
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }

        Section(room.canAddParticipants ? "" : participantCountText) {
            if let participants = Binding($participants) {
                ForEach(participants, id: \.self) { $participant in
                    Menu {
                        if room.canModerate, participant.canBeModerated {
                            if participant.canBeDemoted {
                                Button {
                                    self.changeModerationPermission(forParticipant: participant, canModerate: false)
                                } label: {
                                    Label(NSLocalizedString("Demote from moderator", comment: ""), systemImage: "person")
                                }
                            }

                            if participant.canBePromoted {
                                Button {
                                    self.changeModerationPermission(forParticipant: participant, canModerate: true)
                                } label: {
                                    Label(NSLocalizedString("Promote to moderator", comment: ""), systemImage: "crown")
                                }
                            }
                        }

                        if participant.canBeNotifiedAboutCall, room.permissions.contains(.startCall), room.participantFlags != [] {
                            Button {
                                self.sendCallNotification(forParticipant: participant)
                            } label: {
                                Label(NSLocalizedString("Send call notification", comment: ""), systemImage: "bell")
                            }
                        }

                        if participant.actorType == .email {
                            Button {
                                self.resendInvitation(forParticipant: participant)
                            } label: {
                                Label(NSLocalizedString("Resend invitation", comment: ""), systemImage: "envelope")
                            }
                        }

                        if room.canModerate, participant.canBeModerated {
                            if participant.canBeBanned {
                                Button(role: .destructive) {
                                    participantToBan = participant
                                    banConfirmationShown = true
                                } label: {
                                    Label(NSLocalizedString("Ban participant", comment: ""), systemImage: "person.badge.minus")
                                }
                                .foregroundStyle(.primary)
                                .disabled(isBanActionRunning)
                            }

                            Button(role: .destructive) {
                                Task {
                                    await removeParticipant(participant: participant)
                                }
                            } label: {
                                Label(getRemoveLabel(forParticipant: participant), systemImage: "trash")
                            }
                        }
                    } label: {
                        ContactsTableViewCellWrapper(room: $room, participant: $participant)
                            .frame(height: 72) // Height set in the XIB file
                    }
                    .listRowInsets(.init())
                    .alignmentGuide(.listRowSeparatorLeading) { _ in
                        72
                    }
                }
            } else {
                ProgressView()
                    .listRowInsets(nil)
            }
        }
        .task {
            getParticipants()
        }
        .listRowInsets(room.canAddParticipants ? EdgeInsets(top: -12, leading: 0, bottom: 0, trailing: 0) : nil)
        .alert(String(format: NSLocalizedString("Ban %@", comment: "e.g. Ban John Doe"), participantToBan?.displayName ?? "Unknown"), isPresented: $banConfirmationShown) {
            // Can't move alert inside a menu element, it needs to be outside of the menu

            let banText = NSLocalizedString("Internal note", comment: "Internal note about why a user/guest was banned")
            TextField(banText, text: $internalNote)

            Button(NSLocalizedString("Ban", comment: "Ban a user/guest")) {
                guard let participantToBan else { return }
                banParticipant(participant: participantToBan, withInternalNote: trimmedInternalNote)
            }
            .disabled(trimmedInternalNote.count > 4000)

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Add an internal note about this ban", comment: "")
        }
        // .listSectionSpacing() is only available on iOS 17, but could be an alternative
    }

    func addParticipants() {
        guard let addParticipantsVC = AddParticipantsTableViewController(for: room) else { return }

        self.coordinator = AddParticipantCoordinator(parent: self)
        addParticipantsVC.delegate = self.coordinator
        hostingWrapper.presentViewController(NCNavigationController(rootViewController: addParticipantsVC), animated: true)
    }

    func getParticipants() {
        Task {
            self.participants = try? await NCAPIController.sharedInstance().getParticipants(forRoom: room.token, forAccount: room.account!)
        }
    }

    func getRemoveLabel(forParticipant participant: NCRoomParticipant) -> String {
        if participant.isGroup {
            return NSLocalizedString("Remove group and members", comment: "")
        } else if participant.isTeam {
            return NSLocalizedString("Remove team and members", comment: "")
        }

        return NSLocalizedString("Remove participant", comment: "")
    }

    func changeModerationPermission(forParticipant participant: NCRoomParticipant, canModerate: Bool) {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let method = canModerate ? NCAPIController.sharedInstance().promoteParticipant : NCAPIController.sharedInstance().demoteModerator

        _ = method(participant.participantId, room.token, activeAccount) { error in
            if error != nil {
                NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not change moderation permissions of the participant", comment: ""), withMessage: nil)
            }

            self.getParticipants()
        }
    }

    func sendCallNotification(forParticipant participant: NCRoomParticipant) {
        NCAPIController.sharedInstance().sendCallNotification(toParticipant: String(participant.attendeeId), inRoom: room.token, for: room.account!) { error in
            if error != nil {
                NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not send call notification", comment: ""), withMessage: nil)
            } else {
                NotificationPresenter.shared().present(text: NSLocalizedString("Call notification sent", comment: ""), dismissAfterDelay: 5.0, includedStyle: .success)
            }

            self.getParticipants()
        }
    }

    func resendInvitation(forParticipant participant: NCRoomParticipant) {
        NCAPIController.sharedInstance().resendInvitation(toParticipant: String(participant.attendeeId), inRoom: room.token, for: room.account!) { error in
            if error == nil {
                NotificationPresenter.shared().present(text: NSLocalizedString("Invitation resent", comment: ""), dismissAfterDelay: 5.0, includedStyle: .success)
                NCRoomsManager.sharedInstance().updateRoom(room.token, withCompletionBlock: nil)

                return
            }

            NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not resend email invitations", comment: ""), withMessage: nil)
        }
    }

    func removeParticipant(participant: NCRoomParticipant) async {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let conversationAPIVersion = NCAPIController.sharedInstance().conversationAPIVersion(for: activeAccount)

        if conversationAPIVersion >= APIv3 {
            do {
                try await NCAPIController.sharedInstance().removeAttendee(participant.attendeeId, forRoom: room.token, forAccount: activeAccount)
            } catch {
                NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not remove participant", comment: ""), withMessage: nil)
            }

            self.getParticipants()
            return
        }

        guard let participantId = participant.participantId else { return }

        let method = participant.isGuest ? NCAPIController.sharedInstance().removeGuest : NCAPIController.sharedInstance().removeParticipant

        do {
            _ = try await method(participantId, room.token, activeAccount)
        } catch {
            NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not remove participant", comment: ""), withMessage: nil)
        }

        self.getParticipants()
    }

    func banParticipant(participant: NCRoomParticipant, withInternalNote internalNote: String) {
        guard let actorType = participant.actorType, let actorId = participant.actorId else { return }

        isBanActionRunning = true

        NCAPIController.sharedInstance().banActor(for: room.accountId, in: room.token, with: actorType.rawValue, with: actorId, with: trimmedInternalNote) { success in
            isBanActionRunning = false

            if !success {
                NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Could not ban participant", comment: ""), withMessage: nil)
            }

            self.getParticipants()
        }
    }
}
