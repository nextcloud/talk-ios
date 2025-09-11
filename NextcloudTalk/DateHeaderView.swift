//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

protocol DateHeaderViewDelegate: AnyObject {
    func dateHeaderViewTapped(inSection section: Int)
}

class DateHeaderView: UIView {

    static let maxHeight: CGFloat = 60
    static let horizontalPadding: CGFloat = 32
    static let verticalPadding: CGFloat = 16
    static let labelFont: UIFont = UIFont.preferredFont(forTextStyle: .footnote)

    public var section: Int = 0
    public weak var delegate: DateHeaderViewDelegate?

    public let titleLabel = PaddedLabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupConstraints()
        setupGesture()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
        setupConstraints()
        setupGesture()
    }

    private func setupView() {
        backgroundColor = .clear

        titleLabel.textAlignment = .center
        titleLabel.font = DateHeaderView.labelFont
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.backgroundColor = .secondarySystemGroupedBackground
        titleLabel.textColor = .secondaryLabel
        titleLabel.layer.cornerRadius = 8
        titleLabel.clipsToBounds = true

        if #available(iOS 26.0, *) {
            // When backgroundColor is set to secondarySystemGroupedBackground, the whole view is adjusted
            // when the header is displayed at the top of the scroll view, touching the glass effect
            // making the label unreadable (backgroundColor then equals textColor)
            titleLabel.backgroundColor = .clear
        }

        addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: DateHeaderView.verticalPadding / 2),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -DateHeaderView.verticalPadding / 2),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor, constant: DateHeaderView.horizontalPadding / 2),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor, constant: -DateHeaderView.horizontalPadding / 2),
            titleLabel.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),

            heightAnchor.constraint(lessThanOrEqualToConstant: DateHeaderView.maxHeight)
        ])
    }

    private func setupGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(headerTapped))
        self.addGestureRecognizer(tap)
    }

    @objc private func headerTapped() {
        delegate?.dateHeaderViewTapped(inSection: section)
    }

    static func height(for text: String, fittingWidth width: CGFloat) -> CGFloat {
        let maxLabelWidth = width - horizontalPadding
        let constraintRect = CGSize(width: maxLabelWidth, height: .greatestFiniteMagnitude)

        let boundingRect = text.boundingRect(
            with: constraintRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: labelFont],
            context: nil
        )

        let labelHeight = ceil(boundingRect.height)
        let labelVerticalInsets = PaddedLabel.textInsets.top + PaddedLabel.textInsets.bottom
        let totalHeight = labelHeight + labelVerticalInsets + verticalPadding

        return min(totalHeight, maxHeight)
    }
}
