//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers class ChatOverlayView: UIView, UIGestureRecognizerDelegate {

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var leftIndicator: UIView!
    @IBOutlet weak var backgroundView: UIView!
    @IBOutlet weak var wrapperView: UIView!
    @IBOutlet weak var stackView: UIStackView!

    @IBOutlet weak var title: UILabel!
    @IBOutlet weak var subtitle: UILabel!
    @IBOutlet weak var secondarySubtitle: UILabel!
    @IBOutlet weak var textView: MessageBodyTextView!

    @IBOutlet weak var uiMenuButton: UIButton!

    private var tapToShowMenu: UITapGestureRecognizer?

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
        Bundle.main.loadNibNamed("ChatOverlayView", owner: self, options: nil)
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(contentView)
        contentView.frame = frame
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        if #available(iOS 26.0, *) {
            let effectView = UIVisualEffectView()
            wrapperView.insertSubview(effectView, at: 0)

            let glassEffect = UIGlassEffect(style: .regular)
            effectView.effect = glassEffect
            effectView.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                effectView.leftAnchor.constraint(equalTo: wrapperView.leftAnchor),
                effectView.rightAnchor.constraint(equalTo: wrapperView.rightAnchor),
                effectView.topAnchor.constraint(equalTo: wrapperView.topAnchor),
                effectView.bottomAnchor.constraint(equalTo: wrapperView.bottomAnchor)
            ])

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

        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0

        uiMenuButton.showsMenuAsPrimaryAction = true

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.tapTextView))
        self.tapToShowMenu = tapGestureRecognizer
        tapGestureRecognizer.delegate = self
        tapGestureRecognizer.require(toFail: textView.panGestureRecognizer)

        // Don't open context menu when a link is tapped
        if let linkTap = textView.gestureRecognizers?.first(where: { $0.name == "UITextInteractionNameLinkTap" }) {
            tapGestureRecognizer.require(toFail: linkTap)
        }

        textView.addGestureRecognizer(tapGestureRecognizer)
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

    override func layoutSubviews() {
        super.layoutSubviews()

        guard let font = textView.font else { return }

        // Ensure the labels are correctly sized at this point
        self.stackView.layoutSubviews()

        let singleLineHeight = ceil(font.lineHeight + font.leading)
        let maxViewHeight = singleLineHeight * maxNumberOfLines
        let maxTextSize = ceil(textView.sizeThatFits(CGSize(width: textView.frame.width, height: CGFloat.greatestFiniteMagnitude)).height)

        if maxTextSize > maxViewHeight {
            textView.isScrollEnabled = true

            // We want to indicate that the text is scrollable, so show parts of the next line
            let newHeightConstant = maxViewHeight + (singleLineHeight / 2)
            textView.heightAnchor.constraint(equalToConstant: newHeightConstant).isActive = true
        } else {
            textView.isScrollEnabled = false
            textView.heightAnchor.constraint(equalToConstant: maxViewHeight).isActive = false
        }
    }
}
