//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

public protocol NCChatTitleViewDelegate: AnyObject {
    func chatTitleViewTapped(_ titleView: NCChatTitleView)
}

public class NCChatTitleView: UIView {

    public weak var delegate: NCChatTitleViewDelegate?

    @IBOutlet var contentView: UIView!
    @IBOutlet public weak var titleTextView: UITextView!
    @IBOutlet weak var avatarView: AvatarView!

    public var showSubtitle = true
    public var titleTextColor: UIColor = .label
    public private(set) var longPressGestureRecognizer: UILongPressGestureRecognizer!

    private let titleFont = UIFont.systemFont(ofSize: 16, weight: .semibold)
    private let subtitleFont = UIFont.systemFont(ofSize: 13)

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        Bundle.main.loadNibNamed("NCChatTitleView", owner: self, options: nil)

        addSubview(contentView)
        contentView.frame = bounds

        titleTextView.textContainer.lineFragmentPadding = 0
        titleTextView.textContainerInset = .zero

        if #available(iOS 26.0, *) {
            titleTextColor = .label
        } else {
            titleTextColor = NCAppBranding.themeTextColor()
        }

        // Set empty title on init to prevent showing a placeholder on iPhones in landscape
        setTitle("", withSubtitle: nil)

        // Use a LongPressGestureRecognizer here to get a "TouchDown" event
        longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleGestureRecognizer(_:)))
        longPressGestureRecognizer.minimumPressDuration = 0.0
        contentView.addGestureRecognizer(longPressGestureRecognizer)
    }

    public func update(for room: NCRoom) {
        // Set room image
        avatarView.setAvatar(for: room)

        var subtitle: String?

        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(TalkCapabilityObjC.singleConvStatus) {
            // User status
            avatarView.setStatus(for: room, allowCustomStatusIcon: false)

            // User status message
            if let statusMessage = room.statusMessage, !statusMessage.isEmpty {
                // A dedicated statusMessage was set -> use it
                if let statusIcon = room.statusIcon, !statusIcon.isEmpty {
                    subtitle = "\(statusIcon) \(statusMessage)"
                } else {
                    subtitle = statusMessage
                }
            } else {
                // We don't have a dedicated statusMessage -> check the room status itself
                if room.status == kUserStatusDND {
                    subtitle = NSLocalizedString("Do not disturb", comment: "")
                } else if room.status == kUserStatusAway {
                    subtitle = NSLocalizedString("Away", comment: "")
                }
            }
        }

        // Show description in group conversations
        if room.type != .oneToOne, let roomDescription = room.roomDescription, !roomDescription.isEmpty {
            subtitle = roomDescription
        }

        setTitle(room.displayName, withSubtitle: subtitle)
    }

    public func updateForScheduledMessages(in room: NCRoom) {
        setTitle(NSLocalizedString("Scheduled messages", comment: ""), withSubtitle: room.displayName)
    }

    public func update(for thread: NCThread) {
        // Set thread image
        avatarView.setThreadAvatar(forThread: thread)

        // Set thread title and number of replies
        let repliesString = String.localizedStringWithFormat(NSLocalizedString("%ld replies", comment: "Replies in a thread"), thread.numReplies)
        setTitle(thread.title, withSubtitle: repliesString)
    }

    private func setTitle(_ title: String?, withSubtitle subtitle: String?) {
        guard let title else { return }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail

        let attributedTitle = NSMutableAttributedString(string: title)
        let rangeTitle = NSRange(location: 0, length: title.utf16.count)
        attributedTitle.addAttribute(.font, value: titleFont, range: rangeTitle)
        attributedTitle.addAttribute(.foregroundColor, value: titleTextColor, range: rangeTitle)
        attributedTitle.addAttribute(.paragraphStyle, value: paragraphStyle, range: rangeTitle)

        if showSubtitle, let subtitle {
            let attributedSubtitle = SwiftMarkdownObjCBridge.parseMarkdown(markdownString: NSAttributedString(string: subtitle))
            let rangeSubtitle = NSRange(location: 0, length: attributedSubtitle.length)
            attributedSubtitle.addAttribute(.font, value: subtitleFont, range: rangeSubtitle)
            attributedSubtitle.addAttribute(.foregroundColor, value: titleTextColor, range: rangeSubtitle)
            attributedSubtitle.addAttribute(.paragraphStyle, value: paragraphStyle, range: rangeSubtitle)

            attributedTitle.append(NSAttributedString(string: "\n"))
            attributedTitle.append(attributedSubtitle)

            titleTextView.textContainer.maximumNumberOfLines = 2
        } else {
            titleTextView.textContainer.maximumNumberOfLines = 1
        }

        titleTextView.attributedText = attributedTitle
    }

    @objc private func handleGestureRecognizer(_ gestureRecognizer: UILongPressGestureRecognizer) {
        if gestureRecognizer.state == .began {
            // Simulate a pressed stated. Don't use self.alpha here as it will interfere with NavigationController transitions
            titleTextView.alpha = 0.7
            avatarView.alpha = 0.7
        } else if gestureRecognizer.state == .ended {
            // Call delegate & reset the pressed state -> use dispatch after to give the UI time to show the actual pressed state
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.titleTextView.alpha = 1.0
                self.avatarView.alpha = 1.0

                self.delegate?.chatTitleViewTapped(self)
            }
        }
    }
}
