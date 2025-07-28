//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

protocol MessageSeparatorTableViewCellDelegate: AnyObject {
    func generateSummaryButtonPressed()
}

class MessageSeparatorTableViewCell: UITableViewCell {

    public weak var delegate: MessageSeparatorTableViewCellDelegate?

    public var messageId: Int = 0

    public static let identifier = "MessageSeparatorCellIdentifier"

    public static let unreadMessagesSeparatorId = -99
    public static let unreadMessagesWithSummarySeparatorId = -98
    public static let unreadMessagesSeparatorText = NSLocalizedString("Unread messages", comment: "")

    public static let chatBlockSeparatorId = -97
    public static let chatBlockSeparatorText = NSLocalizedString("Some messages not shown, will be downloaded when online", comment: "")

    public lazy var separatorLabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .clear
        label.isUserInteractionEnabled = false
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label

        return label
    }()

    private lazy var summaryButton: UIButton = {
        let button = NCButton(frame: .zero)

        button.setTitle(NSLocalizedString("Generate summary", comment: ""), for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = button.titleColor(for: .normal)
        button.configuration?.image = UIImage(named: "ai-creation")
        button.configuration?.imagePadding = 8

        button.addAction { [weak self] in
            guard let self else { return }

            self.delegate?.generateSummaryButtonPressed()
            button.setButtonEnabled(enabled: false)
        }

        return button
    }()

    /// `contentStackView` contains the actual content (e.g. separator label and summary button). It can be horizontal or vertical, depending on the size class
    /// | [separatorLabel] [summaryButton] |
    /// or
    /// | [separatorLabel]  |
    /// | [summaryButton] |
    private lazy var contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = self.traitCollection.horizontalSizeClass == .regular ? .horizontal : .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.distribution = .equalSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setContentCompressionResistancePriority(.required, for: .vertical)
        stack.setContentCompressionResistancePriority(.required, for: .horizontal)

        return stack
    }()

    /// `cellStackView` is a UIStackView that spans accross the whole cell. It contains the `contentStackView` and separator lines next to it
    /// | --- [contentStackView] --- |
    private lazy var cellStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 16
        stack.alignment = .center
        stack.distribution = .equalSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setContentCompressionResistancePriority(.required, for: .vertical)
        stack.setContentCompressionResistancePriority(.required, for: .horizontal)

        return stack
    }()

    private func getLineView() -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemFill
        view.isUserInteractionEnabled = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let widthAnchor = view.widthAnchor.constraint(equalToConstant: CGFloat.greatestFiniteMagnitude)
        widthAnchor.priority = .defaultLow

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 1),
            widthAnchor
        ])

        return view
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        self.selectionStyle = .none
        self.contentView.backgroundColor = .systemGroupedBackground

        contentStackView.addArrangedSubview(self.separatorLabel)
        contentStackView.addArrangedSubview(self.summaryButton)
        self.summaryButton.isHidden = true

        self.contentView.addSubview(self.cellStackView)
        NSLayoutConstraint.activate([
            cellStackView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 16),
            cellStackView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -16),
            cellStackView.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 16),
            cellStackView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -16),
            cellStackView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0)
        ])

        let labelLeft = getLineView()
        let labelRight = getLineView()

        cellStackView.addArrangedSubview(labelLeft)
        cellStackView.addArrangedSubview(contentStackView)
        cellStackView.addArrangedSubview(labelRight)

        labelLeft.widthAnchor.constraint(equalTo: labelRight.widthAnchor).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setSummaryButtonVisibilty(isHidden: Bool) {
        self.summaryButton.isHidden = isHidden
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.separatorLabel.text = ""
        self.selectionStyle = .none

        // prepareForReuse is called just before the cell is returned from dequeueReusableCell(), so we can update the axis here
        self.contentStackView.axis = self.traitCollection.horizontalSizeClass == .regular ? .horizontal : .vertical
    }
}
