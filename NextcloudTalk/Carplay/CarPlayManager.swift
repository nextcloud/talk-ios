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

    // Keep the root and its child templates alive for the complete CarPlay
    // connection. Room refreshes only update their sections; they never replace
    // the root hierarchy.
    private var rootTabBarTemplate: CPTabBarTemplate?
    private var conversationsTemplate: CPListTemplate?
    private var callsTemplate: CPListTemplate?

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
        rootTabBarTemplate = nil
        conversationsTemplate = nil
        callsTemplate = nil
    }

    // MARK: - Root

    private func installRootTemplate() {
        guard let interfaceController else {
            return
        }

        let conversations = makeConversationsTemplate()
        conversations.tabTitle = NSLocalizedString("Rooms", comment: "")
        conversations.tabImage = UIImage(systemName: "message.fill")

        let calls = makeCallsTemplate()
        calls.tabTitle = NSLocalizedString("Calls", comment: "")
        calls.tabImage = UIImage(systemName: "phone.fill")

        let root = CPTabBarTemplate(templates: [conversations, calls])

        conversationsTemplate = conversations
        callsTemplate = calls
        rootTabBarTemplate = root

        NCLog.log("CarPlay installing tab root: tabs=2 [Rooms, Calls]")

        interfaceController.setRootTemplate(
            root,
            animated: false,
            completion: { success, error in
                if let error {
                    NCLog.log("CarPlay failed to install tab root: \(error)")
                } else {
                    NCLog.log("CarPlay tab root installed: success=\(success)")
                }
            }
        )
    }

    private func refreshTemplates() {
        guard
            rootTabBarTemplate != nil,
            let conversationsTemplate,
            let callsTemplate
        else {
            // If CarPlay connected while the app was still restoring state,
            // rebuild the complete hierarchy rather than falling back to a
            // single list template.
            installRootTemplate()
            return
        }

        conversationsTemplate.updateSections(makeConversationSections())
        callsTemplate.updateSections(makeCallSections())
    }

    // MARK: - Conversations

    private func makeConversationsTemplate() -> CPListTemplate {
        CPListTemplate(
            title: NSLocalizedString("Rooms", comment: ""),
            sections: makeConversationSections()
        )
    }

    private func makeConversationSections() -> [CPListSection] {
        let rooms = CarPlayConversationProvider.shared.conversations()

        guard !rooms.isEmpty else {
            let emptyItem = CPListItem(
                text: NSLocalizedString("No conversations", comment: ""),
                detailText: nil
            )
            emptyItem.isEnabled = false

            return [CPListSection(items: [emptyItem])]
        }

        let items = rooms
            .prefix(100)
            .map { makeConversationItem($0) }

        return [CPListSection(items: Array(items))]
    }

    private func makeConversationItem(_ room: NCRoom) -> CPListItem {
        let isPhoneRoom = NCTelephonyManager.shared.isPhoneRoom(room)

        let item = CPListItem(
            text: room.displayName,
            detailText: subtitle(for: room),
            image: UIImage(
                systemName: isPhoneRoom ? "phone.circle" : "person.crop.circle"
            )
        )

        item.handler = { [weak self] _, completion in
            self?.showConversation(room)
            completion()
        }

        return item
    }

    private func subtitle(for room: NCRoom) -> String? {
        if NCTelephonyManager.shared.isPhoneRoom(room) {
            return NSLocalizedString("Phone", comment: "")
        }

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

    // MARK: - Calls

    private func makeCallsTemplate() -> CPListTemplate {
        let assistantConfiguration = CPAssistantCellConfiguration(
            position: .top,
            visibility: .always,
            assistantAction: .startCall
        )

        return CPListTemplate(
            title: NSLocalizedString("Calls", comment: ""),
            sections: makeCallSections(),
            assistantCellConfiguration: assistantConfiguration
        )
    }

    private func makeCallSections() -> [CPListSection] {
        let speedDial = CarPlayConversationProvider.shared.speedDial()
        let history = CarPlayConversationProvider.shared.callHistory()

        var sections: [CPListSection] = []

        if !speedDial.isEmpty {
            let items = speedDial
                .prefix(20)
                .map { makeCallItem($0) }

            sections.append(
                CPListSection(
                    items: Array(items),
                    header: NSLocalizedString("Speed Dial", comment: ""),
                    sectionIndexTitle: nil
                )
            )
        }

        if !history.isEmpty {
            let items = history
                .prefix(50)
                .map { makeCallItem($0) }

            sections.append(
                CPListSection(
                    items: Array(items),
                    header: NSLocalizedString("History", comment: ""),
                    sectionIndexTitle: nil
                )
            )
        }

        if sections.isEmpty {
            let emptyItem = CPListItem(
                text: NSLocalizedString("No recent calls", comment: ""),
                detailText: nil
            )
            emptyItem.isEnabled = false
            sections.append(CPListSection(items: [emptyItem]))
        }

        return sections
    }

    private func makeCallItem(_ room: NCRoom) -> CPListItem {
        let isPhone = NCTelephonyManager.shared.isPhoneRoom(room)

        let item = CPListItem(
            text: room.displayName,
            detailText: isPhone
                ? NSLocalizedString("Phone", comment: "")
                : NSLocalizedString("Talk", comment: ""),
            image: UIImage(
                systemName: isPhone
                    ? "phone.fill"
                    : "person.crop.circle.fill"
            )
        )

        item.handler = { _, completion in
            Task { @MainActor in
                do {
                    try await NCCallRouter.shared.call(.room(room))
                } catch {
                    NCLog.log(
                        "CarPlay call routing failed for room=\(room.token): \(error)"
                    )
                }

                completion()
            }
        }

        return item
    }

    // MARK: - Conversation details

    private func showConversation(_ room: NCRoom) {
        guard let interfaceController else {
            return
        }

        let isPhone = NCTelephonyManager.shared.isPhoneRoom(room)

        let contactImage = UIImage(
            systemName: isPhone
                ? "phone.circle"
                : "person.crop.circle"
        ) ?? UIImage()

        let contact = CPContact(
            name: room.displayName,
            image: contactImage
        )

        contact.subtitle = isPhone
            ? NSLocalizedString("Phone", comment: "")
            : NSLocalizedString("Nextcloud Talk", comment: "")

        let callButton = CPContactCallButton { _ in
            Task { @MainActor in
                do {
                    try await NCCallRouter.shared.call(.room(room))
                } catch {
                    NCLog.log(
                        "CarPlay contact call routing failed for room=\(room.token): \(error)"
                    )
                }
            }
        }

        callButton.title = NSLocalizedString("Call", comment: "")
        contact.actions = [callButton]

        interfaceController.pushTemplate(
            CPContactTemplate(contact: contact),
            animated: true,
            completion: nil
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
}
