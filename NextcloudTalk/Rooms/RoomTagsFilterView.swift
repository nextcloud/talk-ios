//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

struct TagFilterChip {
    static let allChipId = "all"

    let id: String
    let title: String
    let unreadCount: Int
    let hasUnreadMention: Bool
}

class RoomTagsFilterView: UIView {

    static let viewHeight: CGFloat = 48

    public var onTagSelected: ((String?) -> Void)?

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var chips: [TagFilterChip] = []
    private var selectedTagId: String?

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
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -8),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor, constant: -16)
        ])
    }

    public func update(chips: [TagFilterChip], selectedTagId: String?) {
        self.chips = chips
        self.selectedTagId = selectedTagId

        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for chip in chips {
            let chipControl = RoomTagChipControl(chip: chip, selected: isSelected(chip))
            chipControl.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            stackView.addArrangedSubview(chipControl)
        }
    }

    private func isSelected(_ chip: TagFilterChip) -> Bool {
        guard let selectedTagId else { return chip.id == TagFilterChip.allChipId }

        return chip.id == selectedTagId
    }

    @objc private func chipTapped(_ sender: RoomTagChipControl) {
        guard let chip = sender.chip else { return }

        // Tapping "All" or the already selected chip clears the tag filter
        if chip.id == TagFilterChip.allChipId || isSelected(chip) {
            onTagSelected?(nil)
        } else {
            onTagSelected?(chip.id)
        }
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
        self.backgroundColor = selected ? NCAppBranding.themeColor() : .secondarySystemFill

        titleLabel.font = .preferredFont(for: .subheadline, weight: .medium)
        titleLabel.text = chip.title
        titleLabel.textColor = selected ? NCAppBranding.themeTextColor() : .label

        contentStackView.axis = .horizontal
        contentStackView.spacing = 8
        contentStackView.alignment = .center
        contentStackView.isUserInteractionEnabled = false
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.addArrangedSubview(titleLabel)

        if chip.unreadCount > 0 {
            // Same unread badge as in the conversation cells
            let badgeView = BadgeView()

            if selected {
                // Invert the badge colors on the theme-colored background
                badgeView.badgeColor = NCAppBranding.themeTextColor()
                badgeView.badgeTextColor = NCAppBranding.themeColor()
                badgeView.badgeHighlightStyle = .important
            } else {
                badgeView.badgeColor = NCAppBranding.themeColor()
                badgeView.badgeTextColor = NCAppBranding.themeTextColor()
                badgeView.badgeHighlightStyle = chip.hasUnreadMention ? .important : .none
            }

            badgeView.setBadgeNumber(chip.unreadCount)
            contentStackView.addArrangedSubview(badgeView)
        }

        self.addSubview(contentStackView)

        // With a badge, use a smaller trailing padding to compensate for
        // the badge's internal padding and its rounded shape
        let trailingPadding: CGFloat = chip.unreadCount > 0 ? 6 : 12

        NSLayoutConstraint.activate([
            contentStackView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 12),
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
