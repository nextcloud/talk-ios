//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import WidgetKit

// Performs the actions of the widget buttons and the Control Center controls (see TalkWidgetIntents)
// and keeps the state they show up to date (see TalkControlsState).
enum TalkWidgetActions {

    // MARK: - Actions

    @available(iOS 17.0, *)
    static func markConversationAsRead(server: String, userId: String, token: String) async throws {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forUserId: userId, inServer: server) else {
            throw TalkIntentError.message(NSLocalizedString("Account not found", comment: ""))
        }

        // Update the widget right away, the server is asked afterwards
        await MainActor.run {
            if let data = ConversationsWidgetData.load(appGroupIdentifier: groupIdentifier) {
                try? data.markingAsRead(token: token).save(appGroupIdentifier: groupIdentifier)
                WidgetCenter.shared.reloadTimelines(ofKind: ConversationsWidgetData.conversationsWidgetKind)
                WidgetCenter.shared.reloadTimelines(ofKind: ConversationsWidgetData.unreadWidgetKind)
            }
        }

        let lastMessageId = NCDatabaseManager.sharedInstance().room(withToken: token, forAccountId: account.accountId)?.lastMessage?.messageId ?? 0

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NCAPIController.sharedInstance().setChatReadMarker(lastMessageId, inRoom: token, forAccount: account) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        // Also updates the widgets with the real state
        NCRoomsManager.shared.updateRooms(updatingUserStatus: false, onlyLastModified: false)
    }

    @available(iOS 17.0, *)
    static func setUserStatus(_ status: String) async throws {
        guard NCDatabaseManager.sharedInstance().numberOfAccounts() > 0 else {
            throw TalkIntentError.message(NSLocalizedString("Account not found", comment: ""))
        }

        let account = NCDatabaseManager.sharedInstance().activeAccount()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NCAPIController.sharedInstance().setUserStatus(status, forAccount: account) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        await MainActor.run {
            self.userStatusDidChange(status)
            NotificationCenter.default.post(name: .TalkWidgetActionsDidChangeUserStatus, object: nil)
        }
    }

    @MainActor
    static func setMicrophoneMuted(_ muted: Bool) {
        NCRoomsManager.shared.callViewController?.setMicrophoneMutedFromControl(muted)
    }

    @MainActor
    static func presentNewConversation() {
        guard NCDatabaseManager.sharedInstance().numberOfAccounts() > 0 else { return }

        NCUserInterfaceController.sharedInstance().presentNewConversation()
    }

    // MARK: - State

    @MainActor
    static func callDidChange(isInCall: Bool, isMicrophoneMuted: Bool) {
        self.updateState { state in
            state.isInCall = isInCall
            state.isMicrophoneMuted = isInCall && isMicrophoneMuted
        }
    }

    @MainActor
    static func userStatusDidChange(_ status: String?) {
        self.updateState { state in
            state.userStatus = status
        }
    }

    @MainActor
    static func accountsDidChange() {
        guard NCDatabaseManager.sharedInstance().numberOfAccounts() == 0 else { return }

        TalkControlsState.remove(appGroupIdentifier: groupIdentifier)
        self.reloadControls()
    }

    @MainActor
    private static func updateState(_ change: (inout TalkControlsState) -> Void) {
        var state = TalkControlsState.load(appGroupIdentifier: groupIdentifier)
        let previousState = state
        change(&state)

        guard state != previousState else { return }

        state.save(appGroupIdentifier: groupIdentifier)
        self.reloadControls()
    }

    @MainActor
    private static func reloadControls() {
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadControls(ofKind: TalkControlsState.muteMicrophoneControlKind)
            ControlCenter.shared.reloadControls(ofKind: TalkControlsState.doNotDisturbControlKind)
        }

        WidgetCenter.shared.reloadTimelines(ofKind: TalkControlsState.statusWidgetKind)
    }
}

extension Notification.Name {
    static let TalkWidgetActionsDidChangeUserStatus = Notification.Name("TalkWidgetActionsDidChangeUserStatus")
}
