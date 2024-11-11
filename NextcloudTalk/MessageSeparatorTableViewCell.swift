//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

class MessageSeparatorTableViewCell: ChatTableViewCell {

    public static let identifier = "MessageSeparatorCellIdentifier"
    public static let cellHeight = 24.0
    public static let unreadMessagesSeparatorId = -99
    public static let chatBlockSeparatorId = -98

    public lazy var separatorLabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .clear
        label.isUserInteractionEnabled = false
        label.numberOfLines = 1
        label.font = .systemFont(ofSize: 12)
        label.text = NSLocalizedString("Unread messages", comment: "")
        label.textColor = .secondaryLabel

        self.contentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.leftAnchor.constraint(equalTo: self.contentView.safeAreaLayoutGuide.leftAnchor, constant: 10),
            label.rightAnchor.constraint(equalTo: self.contentView.safeAreaLayoutGuide.rightAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: self.contentView.safeAreaLayoutGuide.topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: self.contentView.safeAreaLayoutGuide.bottomAnchor, constant: -5),
            label.heightAnchor.constraint(equalToConstant: 14),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 0)
        ])

        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        self.selectionStyle = .none
        self.backgroundColor = .secondarySystemBackground
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.separatorLabel.text = ""
        self.selectionStyle = .none
    }
}
