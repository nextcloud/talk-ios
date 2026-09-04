//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import CarPlay
import UIKit

@available(iOS 14.0, *)
@MainActor
final class CarPlayManager {

    static let shared = CarPlayManager()

    // MARK: - CarPlay

    private weak var interfaceController: CPInterfaceController?

    // MARK: - Init

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(roomsDidUpdate),
            name: .NCRoomsManagerDidUpdateRooms,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(activeAccountDidChange),
            name: .NCSettingsControllerDidChangeActiveAccount,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Connection

    func connect(_ interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController

        refreshRootTemplate()

        NCRoomsManager.shared.updateRooms(
            updatingUserStatus: false,
            onlyLastModified: false
        )
    }

    func disconnect() {
        interfaceController = nil
    }

    // MARK: - Root

    private func refreshRootTemplate() {
        guard let interfaceController else {
            return
        }

        let template = makeConversationsTemplate()

        interfaceController.setRootTemplate(
            template,
            animated: false,
            completion: nil
        )
    }

    // MARK: - Conversations

    private func makeConversationsTemplate() -> CPListTemplate {
        let rooms = CarPlayConversationProvider.shared.conversations()

        if rooms.isEmpty {
            let emptyItem = CPListItem(
                text: NSLocalizedString(
                    "No conversations",
                    comment: ""
                ),
                detailText: nil
            )

            emptyItem.isEnabled = false

            return CPListTemplate(
                title: NSLocalizedString(
                    "Talk",
                    comment: ""
                ),
                sections: [
                    CPListSection(items: [emptyItem])
                ]
            )
        }

        let items: [CPListItem] = rooms
            .prefix(100)
            .map { room in
                makeConversationItem(room)
            }

        let section = CPListSection(
            items: items
        )

        let template = CPListTemplate(
            title: NSLocalizedString(
                "Conversations",
                comment: ""
            ),
            sections: [section]
        )

        return template
    }

    private func makeConversationItem(
        _ room: NCRoom
    ) -> CPListItem {

        let item = CPListItem(
            text: room.displayName,
            detailText: subtitle(for: room),
            image: UIImage(
                systemName: "person.crop.circle"
            )
        )

        item.handler = { [weak self] _, completion in
            self?.showConversation(room)
            completion()
        }

        return item
    }

    private func subtitle(
        for room: NCRoom
    ) -> String? {

        if room.hasCall {
            return NSLocalizedString(
                "Call in progress",
                comment: ""
            )
        }

        if room.unreadMessages > 0 {
            return String.localizedStringWithFormat(
                NSLocalizedString(
                    "%ld unread messages",
                    comment: ""
                ),
                room.unreadMessages
            )
        }

        return nil
    }

    // MARK: - Conversation details

    private func showConversation(
        _ room: NCRoom
    ) {
        guard let interfaceController else {
            return
        }

        let contactImage =
            UIImage(systemName: "person.crop.circle")
            ?? UIImage()

        let contact = CPContact(
            name: room.displayName,
            image: contactImage
        )

        contact.subtitle = NSLocalizedString(
            "Nextcloud Talk",
            comment: ""
        )

        let callButton = CPContactCallButton { [weak self] _ in
            self?.startAudioCall(room)
        }

        callButton.title = NSLocalizedString(
            "Call",
            comment: ""
        )

        contact.actions = [
            callButton
        ]

        let template = CPContactTemplate(
            contact: contact
        )

        interfaceController.pushTemplate(
            template,
            animated: true,
            completion: nil
        )
    }

    // MARK: - Call

    private func startAudioCall(
        _ room: NCRoom
    ) {
        guard
            room.supportsCalling,
            room.userCanStartCall,
            let token = room.token,
            !token.isEmpty
        else {
            return
        }

        let account =
            NCDatabaseManager.sharedInstance().activeAccount()

        CallKitManager.shared.startCall(
            token,
            withVideoEnabled: false,
            andDisplayName: room.displayName,
            asInitiator: true,
            silently: false,
            recordingConsent: false,
            withAccountId: account.accountId
        )
    }

    // MARK: - Notifications

    @objc
    private func roomsDidUpdate() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshRootTemplate()
        }
    }

    @objc
    private func activeAccountDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshRootTemplate()
        }
    }
}
