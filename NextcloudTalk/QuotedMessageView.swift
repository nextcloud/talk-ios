//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers class QuotedMessageView: UIView {

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var quoteBarView: UIView!
    @IBOutlet weak var avatarImageView: AvatarImageView!
    @IBOutlet weak var actorLabel: UILabel!
    @IBOutlet weak var messageLabel: UILabel!

    var highlighted: Bool = false {
        didSet {
            quoteBarView.backgroundColor = highlighted ? NCAppBranding.themeColor() : .systemFill
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    func commonInit() {
        Bundle.main.loadNibNamed("QuotedMessageView", owner: self, options: nil)
        addSubview(contentView)
        contentView.frame = frame
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Quoted message view
        backgroundColor = .clear
        layer.borderColor = UIColor.secondarySystemFill.cgColor
        layer.borderWidth = 1
        layer.cornerRadius = 8

        // Quote bar
        quoteBarView.backgroundColor = .systemFill
        quoteBarView.layer.cornerRadius = quoteBarView.frame.width / 2

        // Avatar
        avatarImageView.layer.cornerRadius = avatarImageView.frame.width / 2
        avatarImageView.layer.masksToBounds = true

        // Labels
        actorLabel.textColor = .secondaryLabel
        actorLabel.font = .preferredFont(forTextStyle: .body)

        messageLabel.textColor = .label
        messageLabel.font = .preferredFont(forTextStyle: .body)
    }
}
