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
    private var rootTemplate: CPListTemplate?
    private var activeCallTemplate: CPContactTemplate?

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(callDidStart(_:)),
            name: .CallKitManagerDidStartCall,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(callDidEnd(_:)),
            name: .CallKitManagerDidEndCall,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Connection

    func connect(_ interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController

        installRootTemplate()

        // Seed Siri with the same one-to-one destinations that CarPlay exposes
        // in Speed Dial. NCIntentController donates both messaging and call
        // interactions for these rooms.
        for room in CarPlayConversationProvider.shared.speedDial().prefix(20)
        where room.type == .oneToOne {
            NCIntentController.sharedInstance().donateSendMessageIntent(for: room)
        }

        NCRoomsManager.shared.updateRooms(
            updatingUserStatus: false,
            onlyLastModified: false
        )
    }

    func disconnect() {
        interfaceController = nil
        rootTemplate = nil
        activeCallTemplate = nil
    }

    // MARK: - Root

    private func installRootTemplate() {
        guard let interfaceController else {
            return
        }

        let assistantConfiguration = CPAssistantCellConfiguration(
            position: .top,
            visibility: .always,
            assistantAction: .startCall
        )

        let root = CPListTemplate(
            title: NSLocalizedString("Talk", comment: ""),
            sections: makeRootSections(),
            assistantCellConfiguration: assistantConfiguration
        )

        rootTemplate = root

        interfaceController.setRootTemplate(
            root,
            animated: false,
            completion: { success, error in
                if let error {
                    NCLog.log("CarPlay failed to install root template: \(error)")
                } else {
                    NCLog.log("CarPlay root template installed: success=\(success)")
                }
            }
        )
    }

    private func refreshTemplates() {
        guard let rootTemplate else {
            installRootTemplate()
            return
        }

        rootTemplate.updateSections(makeRootSections())
    }

    // MARK: - Conversations

    private func makeConversationItem(_ room: NCRoom) -> CPListItem {
        let item = CPListItem(
            text: room.displayName,
            detailText: subtitle(for: room),
            image: UIImage(systemName: "person.crop.circle")
        )
        loadAvatar(for: room, into: item)

        item.handler = { [weak self] _, completion in
            if room.hasCall {
                self?.showInCallView(room)
            } else {
                self?.showConversation(room)
            }

            completion()
        }

        return item
    }

    private func showInCallView(_ room: NCRoom) {
        guard let interfaceController, activeCallTemplate == nil else {
            return
        }

        let contact = CPContact(
            name: room.displayName,
            image: UIImage(systemName: "person.crop.circle") ?? UIImage()
        )

        contact.subtitle = NSLocalizedString("Call in progress", comment: "")

        let endCallButton = CPContactCallButton { [weak self] _ in
            CallKitManager.sharedInstance().endCall(
                room.token,
                withStatusCode: 0
            )

            self?.activeCallTemplate = nil
        }

        endCallButton.title = NSLocalizedString("End call", comment: "")

        contact.actions = [endCallButton]

        let template = CPContactTemplate(contact: contact)
        activeCallTemplate = template

        interfaceController.pushTemplate(
            template,
            animated: true,
            completion: nil
        )
    }

    private func subtitle(for room: NCRoom) -> String? {
        if room.hasCall {
            return NSLocalizedString("Call in progress", comment: "")
        }

        if room.unreadMessages > 0 {
            return String.localizedStringWithFormat(
                NSLocalizedString("%ld unread messages", comment: ""),
                room.unreadMessages
            )
        }

        return nil
    }
    
    private func makeRootSections() -> [CPListSection] {
        let rooms = CarPlayConversationProvider.shared.conversations()

        let ongoingCalls = rooms.filter {
            $0.hasCall
        }

        let favorites = rooms.filter {
            $0.isFavorite && !$0.hasCall
        }

        let otherRooms = rooms.filter {
            !$0.hasCall && !$0.isFavorite
        }

        var sections: [CPListSection] = []

        if !ongoingCalls.isEmpty {
            let items = ongoingCalls
                .prefix(10)
                .map { makeConversationItem($0) }

            sections.append(
                CPListSection(
                    items: Array(items),
                    header: NSLocalizedString("Ongoing calls", comment: ""),
                    sectionIndexTitle: nil
                )
            )
        }

        if !favorites.isEmpty {
            let items = favorites
                .prefix(20)
                .map { makeConversationItem($0) }

            sections.append(
                CPListSection(
                    items: Array(items),
                    header: NSLocalizedString("Favorites", comment: ""),
                    sectionIndexTitle: nil
                )
            )
        }

        if !otherRooms.isEmpty {
            let items = otherRooms
                .prefix(100)
                .map { makeConversationItem($0) }

            sections.append(
                CPListSection(
                    items: Array(items),
                    header: NSLocalizedString("Conversations", comment: ""),
                    sectionIndexTitle: nil
                )
            )
        }

        if sections.isEmpty {
            let item = CPListItem(
                text: NSLocalizedString("No conversations", comment: ""),
                detailText: nil
            )

            item.isEnabled = false
            sections.append(CPListSection(items: [item]))
        }

        return sections
    }
    
    private func loadAvatar(for room: NCRoom, into item: CPListItem) {
        _ = AvatarManager.shared.getAvatar(
            for: room,
            with: UITraitCollection.current.userInterfaceStyle
        ) { image in
            guard let image else {
                return
            }

            DispatchQueue.main.async {
                item.setImage(image)
            }
        }
    }

    // MARK: - Conversation details

    private func showConversation(_ room: NCRoom) {
        guard let interfaceController else {
            return
        }

        let contact = CPContact(
            name: room.displayName,
            image: UIImage(systemName: "person.crop.circle") ?? UIImage()
        )

        contact.subtitle = NSLocalizedString("Nextcloud Talk", comment: "")

        let callButton = CPContactCallButton { [weak self] _ in
            self?.startTalkCall(in: room)
        }

        callButton.title = NSLocalizedString("Call", comment: "")
        contact.actions = [callButton]

        interfaceController.pushTemplate(
            CPContactTemplate(contact: contact),
            animated: true,
            completion: nil
        )
    }

    private func startTalkCall(in room: NCRoom) {
        guard let account = room.account else {
            NCLog.log("CarPlay call rejected: room has no account, room=\(room.token)")
            return
        }

        CallKitManager.sharedInstance().startCall(
            room.token,
            withVideoEnabled: false,
            andDisplayName: room.displayName,
            asInitiator: !room.hasCall,
            silently: false,
            recordingConsent: false,
            withAccountId: account.accountId
        )
    }

    // MARK: - Notifications

    @objc
    private func roomsDidUpdate() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshTemplates()
        }
    }

    @objc
    private func activeAccountDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshTemplates()
        }
    }
    @objc
    private func callDidStart(_ notification: Notification) {
        guard
            let token = notification.userInfo?["roomToken"] as? String,
            let room = CarPlayConversationProvider.shared.room(withToken: token)
        else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.refreshTemplates()
            self?.showInCallView(room)
        }
    }
    @objc
    private func callDidEnd(_ notification: Notification) {
        guard
            notification.userInfo?["roomToken"] as? String != nil
        else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.activeCallTemplate = nil
            self.refreshTemplates()

            self.interfaceController?.popToRootTemplate(
                animated: true,
                completion: nil
            )
        }
    }
}
