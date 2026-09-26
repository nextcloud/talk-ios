//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

protocol DateHeaderViewDelegate: AnyObject {
    func dateHeaderViewTapped(inSection section: Int)
}

class DateHeaderView: UITableViewHeaderFooterView {

    static let reuseIdentifier = "DateHeaderView"

    static let maxHeight: CGFloat = 60
    static let horizontalPadding: CGFloat = 32
    static let verticalPadding: CGFloat = 16
    static let labelFont: UIFont = UIFont.preferredFont(forTextStyle: .footnote)

    public var section: Int = 0
    public weak var delegate: DateHeaderViewDelegate?

    public let titleLabel = PaddedLabel()

    // UIKit does not adapt our colors below the navigation bar, so the label brings its own background
    private let labelBackgroundView = UIView()
    private var labelGlassView: UIVisualEffectView?

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
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
        backgroundConfiguration = .clear()

        titleLabel.textAlignment = .center
        titleLabel.font = DateHeaderView.labelFont
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .secondaryLabel

        labelBackgroundView.clipsToBounds = true

        addSubview(labelBackgroundView)

        if #available(iOS 26.0, *) {
            // A flat color is adjusted until it equals the text color when the header touches the navigation
            // bar, glass stays legible, but animates itself in when created, so these views have to be reused
            let glassView = labelBackgroundView.addGlassView()
            glassView.layer.masksToBounds = true
            labelGlassView = glassView

            // Inside the effect view, so the label and the glass behind it are adapted as one element
            glassView.contentView.addSubview(titleLabel)
        } else {
            labelBackgroundView.backgroundColor = .secondarySystemGroupedBackground
            labelBackgroundView.addSubview(titleLabel)
        }

        labelBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Set here, the height depends on the font size. Glass draws its own edges, so clipping it is not enough
        let cornerRadius = labelBackgroundView.bounds.height / 2

        labelBackgroundView.layer.cornerRadius = cornerRadius
        labelGlassView?.layer.cornerRadius = cornerRadius
    }

    private func setupConstraints() {
        // The glass contentView on iOS 26, labelBackgroundView below that
        guard let labelContainer = titleLabel.superview else { return }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: labelContainer.topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: labelContainer.bottomAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: labelContainer.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: labelContainer.trailingAnchor),

            labelBackgroundView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: DateHeaderView.verticalPadding / 2),
            labelBackgroundView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -DateHeaderView.verticalPadding / 2),
            labelBackgroundView.centerYAnchor.constraint(equalTo: centerYAnchor),

            labelBackgroundView.leadingAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor, constant: DateHeaderView.horizontalPadding / 2),
            labelBackgroundView.trailingAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor, constant: -DateHeaderView.horizontalPadding / 2),
            labelBackgroundView.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),

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
