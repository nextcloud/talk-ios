//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

@objcMembers class InfoLabelTableViewCell: UITableViewCell {

    public static var identifier = "infoLabelTableViewCellIdentifier"

    public var label = UILabel()
    private let labelContainer = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none

        label.numberOfLines = 0
        label.textAlignment = .center
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false

        labelContainer.backgroundColor = .secondarySystemBackground
        labelContainer.layer.cornerRadius = 8
        labelContainer.layer.masksToBounds = true
        labelContainer.translatesAutoresizingMaskIntoConstraints = false

        labelContainer.addSubview(label)
        contentView.addSubview(labelContainer)

        NSLayoutConstraint.activate([
            labelContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            labelContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            labelContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            labelContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: labelContainer.topAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: labelContainer.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: labelContainer.trailingAnchor, constant: -10),
            label.bottomAnchor.constraint(equalTo: labelContainer.bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        label.text = ""
        label.attributedText = nil
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)

        UIView.animate(withDuration: 0.2) {
            self.label.alpha = highlighted ? 0.5 : 1.0
        }
    }
}
