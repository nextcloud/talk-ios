//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Combine
import SwiftyAttributes

protocol PinnedMessageViewDelegate: AnyObject {
    func wantsToScroll(to message: NCChatMessage)
}

@objcMembers class PinnedMessageView: UIView, UIGestureRecognizerDelegate {

    public weak var delegate: PinnedMessageViewDelegate?

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var leftIndicator: UIView!
    @IBOutlet weak var backgroundView: UIView!
    @IBOutlet weak var wrapperView: UIView!
    @IBOutlet weak var stackView: UIStackView!

    @IBOutlet weak var title: UILabel!
    @IBOutlet weak var subtitle: UITextView!

    @IBOutlet weak var uiMenuButton: UIButton!

    private var tapToShowMenu: UITapGestureRecognizer?

    public var message: NCChatMessage?
    public var maxNumberOfLines: CGFloat = 3

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    func commonInit() {
        Bundle.main.loadNibNamed("PinnedMessageView", owner: self, options: nil)
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(contentView)
        contentView.frame = frame
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        if #available(iOS 26.0, *) {
            wrapperView.addGlassView()

            contentView.backgroundColor = .clear
            backgroundView.backgroundColor = .clear
            wrapperView.backgroundColor = .clear
        } else {
            contentView.backgroundColor = .systemBackground
            backgroundView.backgroundColor = NCAppBranding.elementColorBackground()
            wrapperView.backgroundColor = .systemBackground
        }

        leftIndicator.backgroundColor = NCAppBranding.elementColor()

        wrapperView.layer.cornerRadius = 8
        wrapperView.layer.masksToBounds = true

        subtitle.textContainerInset = .zero
        subtitle.textContainer.lineFragmentPadding = 0

        uiMenuButton.showsMenuAsPrimaryAction = true

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.tapTextView))
        self.tapToShowMenu = tapGestureRecognizer
        tapGestureRecognizer.delegate = self
        tapGestureRecognizer.require(toFail: subtitle.panGestureRecognizer)

        subtitle.addGestureRecognizer(tapGestureRecognizer)
        stackView.addGestureRecognizer(tapGestureRecognizer)
        wrapperView.addGestureRecognizer(tapGestureRecognizer)
    }

    func tapTextView() {
        let gestureRecognizer = self.uiMenuButton.gestureRecognizers?.first(where: { $0.description.contains("UITouchDownGestureRecognizer") })
        gestureRecognizer?.touchesBegan([], with: UIEvent())
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

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
        self.subtitle.attributedText = message.messageForLastMessagePreview()

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

    override func layoutSubviews() {
        super.layoutSubviews()

        guard let font = subtitle.font else { return }

        let singleLineHeight = ceil(font.lineHeight + font.leading)
        let maxViewHeight = singleLineHeight * maxNumberOfLines
        let maxTextSize = ceil(subtitle.sizeThatFits(CGSize(width: subtitle.frame.width, height: CGFloat.greatestFiniteMagnitude)).height)

        if maxTextSize > maxViewHeight {
            subtitle.isScrollEnabled = true

            // We want to indicate that the text is scrollable, so show parts of the next line
            let newHeightConstant = maxViewHeight + (singleLineHeight / 2)
            subtitle.heightAnchor.constraint(equalToConstant: newHeightConstant).isActive = true
        } else {
            subtitle.isScrollEnabled = false
            subtitle.heightAnchor.constraint(equalToConstant: maxViewHeight).isActive = false
        }
    }
}
