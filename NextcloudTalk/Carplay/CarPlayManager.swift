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
    private var conversationTemplate: CPContactTemplate?
    private var conversationRoomToken: String?

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
            selector: #selector(callStateDidChange(_:)),
            name: .CallKitManagerDidStartCall,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(callStateDidChange(_:)),
            name: .CallKitManagerDidAnswerCall,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(callStateDidChange(_:)),
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
        conversationTemplate = nil
        conversationRoomToken = nil
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
            title: talkAppName,
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
        refreshConversationTemplate()
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
            self?.showConversation(room)
            completion()
        }

        return item
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
        let traitCollection = UITraitCollection.current

        _ = AvatarManager.shared.getAvatar(
            for: room,
            with: traitCollection.userInterfaceStyle
        ) { image in
            guard let image else {
                return
            }

            item.setImage(
                NCUtils.roundedImage(
                    fromImage: image,
                    traitCollection: traitCollection
                )
            )
        }
    }

    private func loadAvatar(for room: NCRoom, completion: @escaping (UIImage) -> Void) {
        let traitCollection = UITraitCollection.current

        _ = AvatarManager.shared.getAvatar(
            for: room,
            with: traitCollection.userInterfaceStyle
        ) { image in
            guard let image else {
                return
            }

            completion(
                NCUtils.roundedImage(
                    fromImage: image,
                    traitCollection: traitCollection
                )
            )
        }
    }

    // MARK: - Conversation details

    private func showConversation(_ room: NCRoom) {
        guard let interfaceController else {
            return
        }

        let placeholder = UIImage(systemName: "person.crop.circle") ?? UIImage()
        let contact = makeContact(for: room, image: placeholder)
        let template = CPContactTemplate(contact: contact)

        conversationTemplate = template
        conversationRoomToken = room.token

        loadAvatar(for: room) { [weak self, weak template] image in
            guard let self, let template else {
                return
            }

            template.contact = self.makeContact(for: room, image: image)
        }

        interfaceController.pushTemplate(
            template,
            animated: true
        ) { success, error in
            if let error {
                NCLog.log("CarPlay failed to show conversation: \(error)")
                return
            }

            NCLog.log("CarPlay conversation view displayed: success=\(success)")
        }
    }

    private func makeContact(for room: NCRoom, image: UIImage) -> CPContact {
        let contact = CPContact(
            name: room.displayName,
            image: image
        )

        let userIsInCall = isUserInCall(room)

        if room.hasCall || userIsInCall {
            contact.subtitle = NSLocalizedString("Call in progress", comment: "")
        }

        if userIsInCall {
            let endCallImage = UIImage(named: "carplay_end_call")?
                .withRenderingMode(.alwaysOriginal) ?? UIImage()

            let endCallButton = CPButton(image: endCallImage) { [weak self] _ in
                CallKitManager.sharedInstance().endCall(
                    room.token,
                    withStatusCode: 0
                )

                self?.refreshTemplates()
            }

            endCallButton.title = NSLocalizedString("End call", comment: "")
            contact.actions = [endCallButton]
        } else {
            let callButton = CPContactCallButton { [weak self] _ in
                self?.startTalkCall(in: room)
            }

            callButton.title = room.hasCall
                ? NSLocalizedString("Join call", comment: "")
                : NSLocalizedString("Call", comment: "")

            contact.actions = [callButton]
        }

        return contact
    }

    private func refreshConversationTemplate() {
        guard
            let template = conversationTemplate,
            let token = conversationRoomToken,
            let room = CarPlayConversationProvider.shared.room(withToken: token)
        else {
            return
        }

        let placeholder = UIImage(systemName: "person.crop.circle") ?? UIImage()
        template.contact = makeContact(for: room, image: placeholder)

        loadAvatar(for: room) { [weak self, weak template] image in
            guard let self, let template else {
                return
            }

            template.contact = self.makeContact(for: room, image: image)
        }
    }

    private func startTalkCall(in room: NCRoom) {
        guard let account = room.account else {
            NCLog.log("CarPlay call rejected: room has no account, room=\(room.token)")
            return
        }
        
        NCRoomsManager.shared.suppressNextCallUIPresentationForCarPlay()

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
    
    private func isUserInCall(_ room: NCRoom) -> Bool {
        CallKitManager.sharedInstance().calls.values.contains { call in
            call.token == room.token
        }
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
    private func callStateDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.refreshTemplates()
        }
    }
}
