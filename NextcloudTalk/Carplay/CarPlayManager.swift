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

    private weak var interfaceController: CPInterfaceController?
    private var rootTemplate: CPListTemplate?
    private var conversationTemplate: CPContactTemplate?
    private var conversationRoomToken: String?

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
        guard let interfaceController else { return }

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
        root.emptyViewTitleVariants = [NSLocalizedString("No conversations", comment: "")]

        rootTemplate = root

        interfaceController.setRootTemplate(root, animated: false) { _, error in
            if let error {
                NCLog.log("CarPlay failed to install root template: \(error.localizedDescription)")
            }
        }
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

        loadAvatar(for: room) { image in
            item.setImage(image)
        }

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
        let rooms = CarPlayConversationProvider.shared.callableRooms()

        let ongoingCalls = rooms.filter(\.hasCall)
        let favorites = rooms.filter { $0.isFavorite && !$0.hasCall }
        let otherRooms = rooms.filter { !$0.hasCall && !$0.isFavorite }

        var remainingItems = CPListTemplate.maximumItemCount
        let maximumSections = CPListTemplate.maximumSectionCount
        var sections: [CPListSection] = []

        func appendSection(_ rooms: [NCRoom], header: String) {
            guard remainingItems > 0,
                  sections.count < maximumSections,
                  !rooms.isEmpty else {
                return
            }

            let itemCount = min(rooms.count, remainingItems)
            let items = rooms.prefix(itemCount).map { makeConversationItem($0) }

            sections.append(
                CPListSection(
                    items: Array(items),
                    header: header,
                    sectionIndexTitle: nil
                )
            )

            remainingItems -= itemCount
        }

        // Prioritize active calls, then favorites, then the remaining callable rooms.
        appendSection(ongoingCalls, header: NSLocalizedString("Ongoing calls", comment: ""))
        appendSection(favorites, header: NSLocalizedString("Favorites", comment: ""))
        appendSection(otherRooms, header: NSLocalizedString("Conversations", comment: ""))

        return sections
    }

    // MARK: - Avatars

    private var carTraitCollection: UITraitCollection {
        interfaceController?.carTraitCollection ?? UITraitCollection.current
    }

    private func loadAvatar(for room: NCRoom, completion: @escaping (UIImage) -> Void) {
        let traitCollection = carTraitCollection

        _ = AvatarManager.shared.getAvatar(
            for: room,
            with: traitCollection.userInterfaceStyle
        ) { image in
            guard let image else { return }

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
        guard let interfaceController else { return }

        let placeholder = UIImage(systemName: "person.crop.circle") ?? UIImage()
        let template = CPContactTemplate(contact: makeContact(for: room, image: placeholder))

        conversationTemplate = template
        conversationRoomToken = room.token

        loadAvatar(for: room) { [weak self, weak template] image in
            guard let self, let template else { return }
            template.contact = self.makeContact(for: room, image: image)
        }

        interfaceController.pushTemplate(template, animated: true) { _, error in
            if let error {
                NCLog.log("CarPlay failed to show conversation: \(error.localizedDescription)")
            }
        }
    }

    private func makeContact(for room: NCRoom, image: UIImage) -> CPContact {
        let contact = CPContact(name: room.displayName, image: image)
        let userIsInCall = isUserInCall(room)

        if room.hasCall || userIsInCall {
            contact.subtitle = NSLocalizedString("Call in progress", comment: "")
        }

        if userIsInCall {
            let endCallButton = CPButton(image: endCallImage()) { _ in
                CallKitManager.sharedInstance().endCall(room.token, withStatusCode: 0)
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
        guard let template = conversationTemplate,
              let token = conversationRoomToken,
              let room = CarPlayConversationProvider.shared.room(withToken: token) else {
            return
        }

        let placeholder = UIImage(systemName: "person.crop.circle") ?? UIImage()
        template.contact = makeContact(for: room, image: placeholder)

        loadAvatar(for: room) { [weak self, weak template] image in
            guard let self, let template else { return }
            template.contact = self.makeContact(for: room, image: image)
        }
    }

    // MARK: - Calls

    private func startTalkCall(in room: NCRoom) {
        guard let account = room.account else {
            NCLog.log("CarPlay call rejected: room has no account")
            return
        }

        if room.recordingConsent {
            presentRecordingConsent(for: room, account: account)
            return
        }

        startTalkCall(in: room, account: account, recordingConsent: true)
    }

    private func startTalkCall(in room: NCRoom, account: TalkAccount, recordingConsent: Bool) {
        CallKitManager.sharedInstance().startCall(
            room.token,
            withVideoEnabled: false,
            andDisplayName: room.displayName,
            asInitiator: !room.hasCall,
            silently: false,
            recordingConsent: recordingConsent,
            withAccountId: account.accountId
        )
    }

    private func presentRecordingConsent(for room: NCRoom, account: TalkAccount) {
        guard let interfaceController else { return }

        let joinAction = CPAlertAction(
            title: NSLocalizedString(
                "Give consent and join call",
                comment: "Give consent to the recording of the call and join that call"
            ),
            style: .default
        ) { [weak self] _ in
            self?.startTalkCall(in: room, account: account, recordingConsent: true)
        }

        let cancelAction = CPAlertAction(
            title: NSLocalizedString("Cancel", comment: ""),
            style: .cancel
        ) { _ in }

        let template = CPActionSheetTemplate(
            title: "⚠️ " + NSLocalizedString("The call might be recorded", comment: ""),
            message: NSLocalizedString(
                "The recording might include your voice, video from camera, and screen share. Your consent is required before joining the call.",
                comment: ""
            ),
            actions: [joinAction, cancelAction]
        )

        interfaceController.presentTemplate(template, animated: true) { _, error in
            if let error {
                NCLog.log("CarPlay failed to present recording consent: \(error.localizedDescription)")
            }
        }
    }

    private func isUserInCall(_ room: NCRoom) -> Bool {
        CallKitManager.sharedInstance().calls.values.contains { call in
            call.token == room.token && !call.isRinging
        }
    }

    private func endCallImage() -> UIImage {
        let traitCollection = carTraitCollection
        let size = CGSize(width: 64, height: 64)
        let format = UIGraphicsImageRendererFormat()
        format.scale = max(traitCollection.displayScale, 1)
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            UIColor.systemRed.resolvedColor(with: traitCollection).setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()

            let configuration = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
            guard let symbol = UIImage(systemName: "phone.down.fill", withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal),
                  symbol.size.width > 0 else {
                return
            }

            let targetWidth: CGFloat = 30
            let aspectRatio = symbol.size.height / symbol.size.width
            let targetHeight = targetWidth * aspectRatio

            let symbolRect = CGRect(
                x: (size.width - targetWidth) / 2,
                y: (size.height - targetHeight) / 2 + 1,
                width: targetWidth,
                height: targetHeight
            )

            symbol.draw(in: symbolRect)
        }

        return image.withRenderingMode(.alwaysOriginal)
    }

    // MARK: - Notifications

    @objc
    private func roomsDidUpdate() {
        refreshTemplates()
    }

    @objc
    private func activeAccountDidChange() {
        refreshTemplates()
    }

    @objc
    private func callStateDidChange(_: Notification) {
        refreshTemplates()
    }
}
