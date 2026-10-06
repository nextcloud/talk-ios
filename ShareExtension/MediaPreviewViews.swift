//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

// The views of the full screen preview in ShareConfirmationViewController. The file is compiled into the app
// and into the share extension, so nothing in here may use UIApplication.shared.

/// A view that is only there to hold other views: touches that do not hit one of them go through to the
/// views below, which is what lets the media underneath be swiped.
final class MediaPreviewPassthroughView: UIView {

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)

        return hitView === self ? nil : hitView
    }
}

/// A dark blurred capsule that stays readable on top of any photo.
class MediaPreviewCapsuleView: UIVisualEffectView {

    init() {
        super.init(effect: UIBlurEffect(style: .systemThinMaterialDark))

        self.translatesAutoresizingMaskIntoConstraints = false
        self.clipsToBounds = true
        self.layer.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.layer.cornerRadius = self.bounds.height / 2
    }
}

/// The pill with the position of the shown item, like "2 of 5".
final class MediaPreviewCounterView: MediaPreviewCapsuleView {

    private let label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white

        return label
    }()

    override init() {
        super.init()

        self.contentView.addSubview(self.label)

        NSLayoutConstraint.activate([
            self.label.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 12),
            self.label.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -12),
            self.label.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 6),
            self.label.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -6)
        ])

        self.isAccessibilityElement = true
        self.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows the position, hidden as long as there is only one item to tell apart. `current` starts at 1.
    func update(current: Int, total: Int) {
        let text = String.localizedStringWithFormat(NSLocalizedString("%1$ld of %2$ld", comment: "Position of the shown item in the selection, e.g. '2 of 5'"), current, total)

        self.label.text = text
        self.accessibilityLabel = text
        self.isHidden = total < 2
    }
}

/// The pill with the buttons that act on the shown item.
final class MediaPreviewToolsView: MediaPreviewCapsuleView {

    private let stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 0

        return stackView
    }()

    init(buttons: [UIButton]) {
        super.init()

        for button in buttons {
            self.stackView.addArrangedSubview(button)
        }

        self.contentView.addSubview(self.stackView)

        NSLayoutConstraint.activate([
            self.stackView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 4),
            self.stackView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -4),
            self.stackView.topAnchor.constraint(equalTo: self.contentView.topAnchor),
            self.stackView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// A white icon button with a touch target of the recommended size.
    static func toolButton(systemName: String, accessibilityLabel: String) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = .white
        button.accessibilityLabel = accessibilityLabel

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 48),
            button.heightAnchor.constraint(equalToConstant: 44)
        ])

        return button
    }
}
