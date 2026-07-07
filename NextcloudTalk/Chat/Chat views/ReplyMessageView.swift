//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

@objcMembers class ReplyMessageView: UIView, SLKVisibleViewProtocol {

    dynamic var isVisible: Bool = false

    var message: NCChatMessage?

    lazy var quotedMessageView: QuotedMessageView = {
        let quotedMessageView = QuotedMessageView()
        quotedMessageView.translatesAutoresizingMaskIntoConstraints = false

        return quotedMessageView
    }()

    lazy var topBorder: CALayer = {
        let topBorder = CAGradientLayer()
        topBorder.frame = CGRect(x: 0, y: 0, width: frame.size.width, height: 1)
        topBorder.backgroundColor = UIColor.quaternarySystemFill.cgColor

        return topBorder
    }()

    private lazy var quoteContainerView: UIView = {
        let quoteContainerView = UIView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        quoteContainerView.translatesAutoresizingMaskIntoConstraints = false

        return quoteContainerView
    }()

    private lazy var cancelButton: UIButton = {
        let cancelButton = UIButton(type: .system)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.titleLabel?.font = .boldSystemFont(ofSize: 15)
        cancelButton.setImage(UIImage(systemName: "xmark.circle"), for: .normal)
        cancelButton.addTarget(self, action: #selector(dismiss), for: .touchUpInside)

        return cancelButton
    }()

    private var cancelButtonWidthConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureSubviews() {
        backgroundColor = .systemBackground

        addSubview(quoteContainerView)
        addSubview(cancelButton)
        layer.addSublayer(topBorder)

        quoteContainerView.addSubview(quotedMessageView)

        cancelButtonWidthConstraint = cancelButton.widthAnchor.constraint(equalToConstant: 44)

        NSLayoutConstraint.activate([
            quoteContainerView.leftAnchor.constraint(equalTo: safeAreaLayoutGuide.leftAnchor, constant: 16),

            cancelButton.leftAnchor.constraint(equalTo: quoteContainerView.rightAnchor, constant: 4),

            cancelButton.rightAnchor.constraint(equalTo: safeAreaLayoutGuide.rightAnchor, constant: -4),
            cancelButtonWidthConstraint,
            quotedMessageView.widthAnchor.constraint(equalTo: quoteContainerView.widthAnchor),

            quoteContainerView.topAnchor.constraint(equalTo: topAnchor),
            quoteContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            cancelButton.topAnchor.constraint(equalTo: topAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: bottomAnchor),

            quotedMessageView.centerYAnchor.constraint(equalTo: quoteContainerView.centerYAnchor)
        ])
    }

    // MARK: - UIView

    override func layoutSubviews() {
        super.layoutSubviews()

        topBorder.frame = CGRect(x: 0, y: 0, width: bounds.size.width, height: 1)
    }

    override var intrinsicContentSize: CGSize {
        // This will indicate the size of the view when calling systemLayoutSizeFittingSize in SLKTextViewController
        // QuoteMessageView(60) + 2*Padding(8)
        return CGSize(width: UIView.noIntrinsicMetric, height: 76)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            // We use a CGColor so we loose the automatic color changing of dynamic colors -> update manually
            topBorder.backgroundColor = UIColor.quaternarySystemFill.cgColor
        }
    }

    // MARK: - SLKReplyViewProtocol

    func dismiss() {
        if isVisible {
            isVisible = false
        }
    }

    // MARK: - ReplyMessageView

    func presentReply(with message: NCChatMessage, withUserId userId: String) {
        self.message = message

        let actorDisplayName = message.actorDisplayName ?? ""
        quotedMessageView.actorLabel.text = actorDisplayName.isEmpty ? NSLocalizedString("Guest", comment: "") : actorDisplayName

        let attributedMessage = NSMutableAttributedString(attributedString: message.messageForLastMessagePreview() ?? NSAttributedString())
        attributedMessage.addAttribute(.font, value: quotedMessageView.messageLabel.font!, range: NSRange(location: 0, length: attributedMessage.length))
        quotedMessageView.messageLabel.attributedText = attributedMessage
        quotedMessageView.highlighted = message.isMessage(from: userId)

        if let account = message.account {
            quotedMessageView.avatarImageView.setActorAvatar(forMessage: message, withAccount: account)
        }

        cancelButton.isHidden = false

        // Reset button size to 44 in case it was hidden before
        cancelButtonWidthConstraint.constant = 44

        isVisible = true
    }

    func hideCloseButton() {
        cancelButton.isHidden = true
        // With 2*4 padding (left and right to the button) we add 8 to have 16 as we have on the left side of the quoteView
        cancelButtonWidthConstraint.constant = 8
    }
}
