//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

protocol SystemMessageTableViewCellDelegate: AnyObject {
    func cellWantsToCollapseMessages(with message: NCChatMessage)
}

class SystemMessageTableViewCell: UITableViewCell {

    public weak var delegate: SystemMessageTableViewCellDelegate?

    public var messageId: Int = 0
    public var message: NCChatMessage?

    private var didCreateSubviews = false

    public static let identifier = "SystemMessageCellIdentifier"

    public lazy var bodyTextView = {
        let textView = MessageBodyTextView()
        textView.dataDetectorTypes = []

        return textView
    }()

    public lazy var dateLabel = {
        let label = UILabel()
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .clear
        label.isUserInteractionEnabled = false
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel

        return label
    }()

    private lazy var collapseButton: UIButton = {
        let button = UIButton(frame: .init(x: 0, y: 0, width: 40, height: 20))

        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .tertiaryLabel
        button.setImage(UIImage(systemName: "rectangle.arrowtriangle.2.inward"), for: .normal)

        button.addAction { [weak self] in
            guard let self, let message else { return }

            self.delegate?.cellWantsToCollapseMessages(with: message)
        }

        return button
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        self.selectionStyle = .none
        self.backgroundColor = .systemBackground
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        guard self.didCreateSubviews else { return }

        self.selectionStyle = .none
        self.backgroundColor = .systemBackground

        self.bodyTextView.text = ""
        self.dateLabel.text = ""
    }

    public func setup(for message: NCChatMessage) {
        // swiftlint:disable:next empty_count
        self.collapseButton.isHidden = (message.isCollapsed || message.collapsedMessages.count == 0)

        // If the message is not visible, we don't need to setup this cell
        if message.isCollapsed && message.collapsedBy != nil {
            return
        }

        if !self.didCreateSubviews {
            self.configureSubviews()
        }

        self.bodyTextView.attributedText = message.systemMessageFormat
        self.messageId = message.messageId
        self.message = message

        if !message.isGroupMessage && !(message.isCollapsed && message.collapsedBy != nil) {
            let date = Date(timeIntervalSince1970: TimeInterval(message.timestamp))

            self.dateLabel.text = NCUtils.getTime(fromDate: date)
        }

        // swiftlint:disable:next empty_count
        if !message.isCollapsed && (message.collapsedBy != nil || message.collapsedMessages.count > 0) {
            self.backgroundColor = .tertiarySystemFill
        } else {
            self.backgroundColor = .systemBackground
        }

        // swiftlint:disable:next empty_count
        if message.collapsedMessages.count > 0 {
            self.selectionStyle = .default
        } else {
            self.selectionStyle = .none
        }
    }

    func configureSubviews() {
        self.contentView.addSubview(self.dateLabel)
        self.contentView.addSubview(self.bodyTextView)
        self.contentView.addSubview(self.collapseButton)

        let views = [
            "dateLabel": self.dateLabel,
            "bodyTextView": self.bodyTextView,
            "collapseButton": self.collapseButton
        ]

        let metrics = [
            "dateLabelWidth": 40,
            "avatarGap": 50,
            "right": 10,
            "left": 5
        ]

        self.contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-avatarGap-[bodyTextView]-[dateLabel(>=dateLabelWidth)]-right-|", metrics: metrics, views: views))
        self.contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-left-[collapseButton(40)]-left-[bodyTextView]-[dateLabel(>=dateLabelWidth)]-right-|", metrics: metrics, views: views))

        self.bodyTextView.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor).isActive = true
        self.dateLabel.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor).isActive = true
        self.collapseButton.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor).isActive = true

        self.didCreateSubviews = true
    }

}
