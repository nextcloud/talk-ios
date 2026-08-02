//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

@objcMembers class ReplyMessageView: UIView, SLKVisibleViewProtocol {

    dynamic var isVisible: Bool = false {
        didSet {
            guard isVisible != oldValue else { return }

            // Fade along with the height animation of the SLKTextViewController, our content does not shrink
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
                self.alpha = self.isVisible ? 1 : 0
            }
        }
    }

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

    /// Glass background, only used on iOS 26 and above
    private var backgroundView: UIVisualEffectView?

    /// Corner radius of the glass background, set by the InputbarViewController to match the textView below
    internal var backgroundCornerRadius: CGFloat = 22 {
        didSet {
            backgroundView?.layer.cornerRadius = backgroundCornerRadius
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureSubviews() {
        // We start out hidden, so the first presentation fades in
        alpha = 0

        addSubview(quoteContainerView)
        addSubview(cancelButton)

        if #available(iOS 26.0, *) {
            // The chat content scrolls behind the reply view, so it needs its own glass background
            let backgroundView = UIVisualEffectView(effect: UIGlassEffect())
            backgroundView.translatesAutoresizingMaskIntoConstraints = false
            backgroundView.isUserInteractionEnabled = false
            backgroundView.clipsToBounds = true
            backgroundView.layer.cornerCurve = .continuous
            backgroundView.layer.cornerRadius = backgroundCornerRadius

            insertSubview(backgroundView, at: 0)
            self.backgroundView = backgroundView

            NSLayoutConstraint.activate([
                backgroundView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 8),
                backgroundView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -8),
                backgroundView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
            ])
        } else {
            backgroundColor = .systemBackground
            layer.addSublayer(topBorder)
        }

        quoteContainerView.addSubview(quotedMessageView)

        // The glass background provides the frame, so the quoted message itself stays chrome-less. Only done for
        // our own instance, the one inside a chat bubble keeps its border.
        var cancelButtonRightInset: CGFloat = -4

        if #available(iOS 26.0, *) {
            quotedMessageView.layer.borderWidth = 0
            quotedMessageView.layer.cornerRadius = 0

            // Keep the cancel button inside the glass background
            cancelButtonRightInset = -12
        }

        cancelButtonWidthConstraint = cancelButton.widthAnchor.constraint(equalToConstant: 44)

        NSLayoutConstraint.activate([
            quoteContainerView.leftAnchor.constraint(equalTo: safeAreaLayoutGuide.leftAnchor, constant: 16),

            cancelButton.leftAnchor.constraint(equalTo: quoteContainerView.rightAnchor, constant: 4),

            cancelButton.rightAnchor.constraint(equalTo: safeAreaLayoutGuide.rightAnchor, constant: cancelButtonRightInset),
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

        quotedMessageView.actorLabel.attributedText = message.quotedActorLabel

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
