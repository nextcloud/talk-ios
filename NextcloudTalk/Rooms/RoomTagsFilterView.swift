//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

struct TagFilterChip {
    static let allChipId = "all"
    static let threadsChipId = "threads"
    static let archivedChipId = "archived"

    let id: String
    let title: String
    let unreadCount: Int
    let mentioned: Bool
    let groupMentioned: Bool
    let showsUnreadDot: Bool
    let icon: UIImage?

    init(id: String, title: String, unreadCount: Int = 0, mentioned: Bool = false, groupMentioned: Bool = false, showsUnreadDot: Bool = false, icon: UIImage? = nil) {
        self.id = id
        self.title = title
        self.unreadCount = unreadCount
        self.mentioned = mentioned
        self.groupMentioned = groupMentioned
        self.showsUnreadDot = showsUnreadDot
        self.icon = icon
    }
}

class RoomTagsFilterView: UIView {

    static let chipVerticalPadding: CGFloat = PillShapeMetrics.verticalPadding
    static let rowVerticalPadding: CGFloat = 8

    // Adapts to the current dynamic type size of the chip title font
    static var viewHeight: CGFloat {
        let titleHeight = ceil(UIFont.preferredFont(forTextStyle: .headline).lineHeight)
        return titleHeight + chipVerticalPadding * 2 + rowVerticalPadding * 2
    }

    public var onChipSelected: ((String) -> Void)?
    public var onChipLongPressed: (() -> Void)?

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let feedbackGenerator = UISelectionFeedbackGenerator()
    private var chips: [TagFilterChip] = []
    private var selectedChipId: String = TagFilterChip.allChipId

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(scrollView)

        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: self.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: self.bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: Self.rowVerticalPadding),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -Self.rowVerticalPadding),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor, constant: -(Self.rowVerticalPadding * 2))
        ])
    }

    public func update(chips: [TagFilterChip], selectedChipId: String) {
        self.chips = chips
        self.selectedChipId = selectedChipId

        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for chip in chips {
            let chipControl = RoomTagChipControl(chip: chip, selected: chip.id == selectedChipId)
            chipControl.addTarget(self, action: #selector(chipTouchedDown(_:)), for: .touchDown)
            chipControl.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            chipControl.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(chipLongPressed(_:))))
            stackView.addArrangedSubview(chipControl)
        }
    }

    @objc private func chipLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }

        feedbackGenerator.selectionChanged()
        onChipLongPressed?()
    }

    @objc private func chipTouchedDown(_ sender: RoomTagChipControl) {
        // Wake up the Taptic Engine, so the feedback on touch up plays without delay
        feedbackGenerator.prepare()
    }

    @objc private func chipTapped(_ sender: RoomTagChipControl) {
        guard let chip = sender.chip else { return }

        feedbackGenerator.selectionChanged()
        onChipSelected?(chip.id)
    }
}

private class RoomTagChipControl: UIControl {

    public private(set) var chip: TagFilterChip?

    private let titleLabel = UILabel()
    private let contentStackView = UIStackView()

    init(chip: TagFilterChip, selected: Bool) {
        super.init(frame: .zero)

        self.chip = chip
        self.layer.masksToBounds = true
        // Same background as InfoLabelTableViewCell (e.g. pending invitations row)
        self.backgroundColor = selected ? NCAppBranding.themeColor() : .secondarySystemBackground

        // Same font as the title in the conversation cells
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.text = chip.title
        titleLabel.textColor = selected ? NCAppBranding.themeTextColor() : .label

        contentStackView.axis = .horizontal
        contentStackView.spacing = 8
        contentStackView.alignment = .center
        contentStackView.isUserInteractionEnabled = false
        contentStackView.translatesAutoresizingMaskIntoConstraints = false

        if let icon = chip.icon {
            let iconView = UIImageView(image: icon)
            iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .headline, scale: .small)
            iconView.tintColor = selected ? NCAppBranding.themeTextColor() : .label
            contentStackView.addArrangedSubview(iconView)
            contentStackView.setCustomSpacing(6, after: iconView)
        }

        contentStackView.addArrangedSubview(titleLabel)

        if chip.unreadCount > 0 {
            // Same unread badge as in the conversation cells
            let badgeView = BadgeView()

            if selected {
                // Invert the badge colors on the theme-colored background
                badgeView.badgeColor = NCAppBranding.themeTextColor()
                badgeView.badgeTextColor = NCAppBranding.themeColor()
            } else {
                badgeView.badgeColor = NCAppBranding.themeColor()
                badgeView.badgeTextColor = NCAppBranding.themeTextColor()
            }

            if chip.mentioned {
                badgeView.badgeHighlightStyle = .important
            } else if chip.groupMentioned {
                badgeView.badgeHighlightStyle = .border
            } else {
                badgeView.badgeHighlightStyle = selected ? .important : .none
            }

            badgeView.setBadgeNumber(chip.unreadCount)
            contentStackView.addArrangedSubview(badgeView)
        } else if chip.showsUnreadDot {
            // Unread mention indicator without a number, to not grab too much attention
            let dotView = UIView()
            dotView.backgroundColor = selected ? NCAppBranding.themeTextColor() : NCAppBranding.elementColor()
            dotView.layer.cornerRadius = 4

            NSLayoutConstraint.activate([
                dotView.widthAnchor.constraint(equalToConstant: 8),
                dotView.heightAnchor.constraint(equalToConstant: 8)
            ])

            contentStackView.addArrangedSubview(dotView)
        }

        self.addSubview(contentStackView)

        // With a badge, use a smaller trailing padding to compensate for
        // the badge's internal padding and its rounded shape
        let trailingPadding: CGFloat = chip.unreadCount > 0 ? PillShapeMetrics.horizontalPadding - 6 : PillShapeMetrics.horizontalPadding

        NSLayoutConstraint.activate([
            contentStackView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: PillShapeMetrics.horizontalPadding),
            contentStackView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -trailingPadding),
            contentStackView.topAnchor.constraint(equalTo: self.topAnchor, constant: 2),
            contentStackView.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -2)
        ])

        self.isAccessibilityElement = true
        self.accessibilityLabel = chip.title
        self.accessibilityTraits = selected ? [.button, .selected] : [.button]

        if chip.unreadCount > 0 {
            let format = NSLocalizedString("%ld conversations with unread messages", comment: "Accessibility label for unread counter on a tag filter")
            self.accessibilityValue = String(format: format, chip.unreadCount)
        } else if chip.showsUnreadDot {
            self.accessibilityValue = NSLocalizedString("Unread mentions", comment: "")
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.layer.cornerRadius = self.bounds.height / 2
    }

    override var isHighlighted: Bool {
        didSet {
            self.alpha = isHighlighted ? 0.6 : 1.0
        }
    }
}
