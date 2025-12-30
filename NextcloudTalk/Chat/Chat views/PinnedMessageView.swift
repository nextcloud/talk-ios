//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SwiftyAttributes

protocol PinnedMessageViewDelegate: AnyObject {
    func wantsToScroll(to message: NCChatMessage)
}

@objcMembers class PinnedMessageView: ChatOverlayView {

    public weak var delegate: PinnedMessageViewDelegate?

    public var message: NCChatMessage?

    public func setupPinnedMessage(withMessage message: NCChatMessage, inRoom room: NCRoom) {
        guard let account = room.account else { return }

        self.message = message

        let messageActor = message.actor
        let titleLabel = messageActor.attributedDisplayName
        var menuActions = [UIMenuElement]()

        if let pinnedActorDisplayName = message.pinnedActorDisplayName, (message.pinnedActorId != message.actorId || message.pinnedActorType != "users") {
            var editedString = NSLocalizedString("pinned by", comment: "A message was pinned by ...")
            editedString = " (\(editedString) \(pinnedActorDisplayName))"

            let editedAttributedString = editedString.withTextColor(.tertiaryLabel)

            titleLabel.append(editedAttributedString)
        }

        self.title.attributedText = titleLabel
        self.textView.attributedText = message.messageForLastMessagePreview()
        self.subtitle.isHidden = true
        self.secondarySubtitle.isHidden = true

        var pinnedInfoText: String

        if message.pinnedUntil > 0 {
            let pinnedUntilDate = Date(timeIntervalSince1970: TimeInterval(message.pinnedUntil))
            pinnedInfoText = String(format: NSLocalizedString("Pinned until %@", comment: "Message is pinned until …"), NCUtils.readableTimeAndDate(fromDate: pinnedUntilDate))
        } else {
            let pinnedAtDate = Date(timeIntervalSince1970: TimeInterval(message.pinnedAt))
            pinnedInfoText = String(format: NSLocalizedString("Pinned at %@", comment: "Message was pinned at …"), NCUtils.readableTimeAndDate(fromDate: pinnedAtDate))
        }

        let pinnedUntilAction = UIAction(title: pinnedInfoText, attributes: [.disabled], handler: {_ in })
        menuActions.append(UIMenu(options: [.displayInline], children: [pinnedUntilAction]))

        let gotoAction = UIAction(title: NSLocalizedString("Go to message", comment: ""), image: UIImage(systemName: "text.bubble")) { [unowned self] _ in
            self.delegate?.wantsToScroll(to: message)
        }

        menuActions.append(gotoAction)

        let hideAction = UIAction(title: NSLocalizedString("Hide", comment: ""), image: UIImage(systemName: "eye.slash")) { [unowned self] _ in
            Task { @MainActor in
                try await NCAPIController.sharedInstance().unpinMessageForSelf(message.messageId, inRoom: room.token, forAccount: account)
                self.removeFromSuperview()
            }
        }

        menuActions.append(hideAction)

        if room.canModerate {
            let unpinAction = UIAction(title: NSLocalizedString("Unpin", comment: ""), image: UIImage(systemName: "pin.slash")) { [unowned self] _ in
                Task { @MainActor in
                    try await NCAPIController.sharedInstance().unpinMessage(message.messageId, inRoom: room.token, forAccount: account)
                    self.removeFromSuperview()
                }
            }

            menuActions.append(unpinAction)
        }

        uiMenuButton.menu = UIMenu(children: menuActions)
    }

}
