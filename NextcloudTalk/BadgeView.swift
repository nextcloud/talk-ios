//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

class BadgeView: UIView {

    enum BadgeHighlightStyle {
        case none
        case border
        case important
    }

    private let badgeNumberLimit = 9999

    private let defaultBadgeColor: UIColor = .systemGray3
    private let defaultBadgeTextColor: UIColor = .label

    private let horizontalPadding: CGFloat = 8
    private let verticalPadding: CGFloat = 4

    private let label = UILabel()

    var badgeColor: UIColor = .red
    var badgeTextColor: UIColor = .white
    var badgeHighlightStyle: BadgeHighlightStyle = .important

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        label.textAlignment = .center
        label.textColor = .label
        label.font = UIFont.preferredFont(for: .footnote, weight: .bold)
        label.adjustsFontForContentSizeCategory = true
        label.layer.masksToBounds = true

        self.addSubview(label)
    }

    func setBadgeNumber(_ number: Int) {
        if number == 0 {
            label.text = ""
            invalidateIntrinsicContentSize()
            return
        }

        if number > badgeNumberLimit {
            label.text = "\(badgeNumberLimit)+"
        } else {
            label.text = "\(number)"
        }

        let width = label.intrinsicContentSize.width + horizontalPadding * 2
        let height = label.intrinsicContentSize.height + verticalPadding * 2
        let finalWidth = width < height ? height : width

        // Perform badge view resizing and setting badge color without animations
        UIView.performWithoutAnimation {
            layer.cornerRadius = height / 2
            frame.size = CGSize(width: finalWidth, height: height)

            label.frame.size = CGSize(width: finalWidth, height: height)
            label.center = CGPoint(x: finalWidth / 2, y: height / 2)

            setBadgeColor(style: badgeHighlightStyle)
        }

        invalidateIntrinsicContentSize()
    }

    func setBadgeColor(style: BadgeHighlightStyle) {
        switch style {
        case .none:
            layer.borderWidth = 0
            backgroundColor = defaultBadgeColor
            label.textColor = defaultBadgeTextColor
        case .border:
            layer.borderWidth = 2
            layer.borderColor = badgeColor.cgColor
            backgroundColor = .clear
            label.textColor = badgeColor
        case .important:
            layer.borderWidth = 0
            backgroundColor = badgeColor
            label.textColor = badgeTextColor
        }
    }

    override var intrinsicContentSize: CGSize {
        guard let text = label.text, !text.isEmpty else { return .zero }

        let width = label.intrinsicContentSize.width + horizontalPadding * 2
        let height = label.intrinsicContentSize.height + verticalPadding * 2
        let finalWidth = width < height ? height : width

        return CGSize(width: finalWidth, height: height)
    }
}
