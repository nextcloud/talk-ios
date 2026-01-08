//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

class AutoCompletionTableViewCell: UITableViewCell {

    public static let identifier = "AutoCompletionCellIdentifier"
    public static let cellHeight = 50.0

    private let avatarHeight = 30.0

    public lazy var titleLabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .clear
        label.isUserInteractionEnabled = false
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label

        return label
    }()

    public lazy var avatarButton = {
        let button = AvatarButton(frame: .init(x: 0, y: 0, width: avatarHeight, height: avatarHeight))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = NCAppBranding.placeholderColor()
        button.layer.cornerRadius = avatarHeight / 2
        button.layer.masksToBounds = true
        button.showsMenuAsPrimaryAction = true
        button.imageView?.contentMode = .scaleToFill

        return button
    }()

    private lazy var userStatusImageView = {
        let imageView = UIImageView(frame: .init(x: 0, y: 0, width: 12, height: 12))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = false

        return imageView
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        self.backgroundColor = .secondarySystemBackground
        self.configureSubviews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        self.titleLabel.font = .preferredFont(forTextStyle: .body)
        self.titleLabel.text = ""

        self.avatarButton.prepareForReuse()

        self.userStatusImageView.image = nil
        self.userStatusImageView.backgroundColor = .clear
    }

    func configureSubviews() {
        self.contentView.addSubview(self.avatarButton)
        self.contentView.addSubview(self.userStatusImageView)
        self.contentView.addSubview(self.titleLabel)

        let views = [
            "avatarButton": self.avatarButton,
            "userStatusImageView": self.userStatusImageView,
            "titleLabel": self.titleLabel
        ]

        let metrics = [
            "avatarSize": avatarHeight,
            "right": 10
        ]

        self.contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-right-[avatarButton(avatarSize)]-right-[titleLabel]-right-|", metrics: metrics, views: views))
        self.contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[titleLabel]|", metrics: metrics, views: views))
        self.contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-32-[userStatusImageView(12)]-(>=0)-|", metrics: metrics, views: views))
        self.contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-32-[userStatusImageView(12)]-(>=0)-|", metrics: metrics, views: views))
        self.contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-right-[avatarButton(avatarSize)]-(>=0)-|", metrics: metrics, views: views))
    }

    public func setUserStatus(_ status: String) {
        var statusImage: UIImage?

        if status == "online" {
            statusImage = NCUserStatus.getOnlineSFIcon()
        } else if status == "away" {
            statusImage = NCUserStatus.getAwaySFIcon()
        } else if status == "busy" {
            statusImage = NCUserStatus.getBusySFIcon()
        } else if status == "dnd" {
            statusImage = NCUserStatus.getDoNotDisturbSFIcon()
        }

        if let statusImage = NCUtils.renderAspectImage(image: statusImage, ofSize: .init(width: 10, height: 10), centerImage: false) {
            userStatusImageView.image = statusImage
            userStatusImageView.contentMode = .center
            userStatusImageView.layer.cornerRadius = 6
            userStatusImageView.clipsToBounds = true

            // When a background color is set directly to the cell it seems that there is no background configuration.
            // In this class, even when no background color is set, the background configuration is nil.
            userStatusImageView.backgroundColor = self.backgroundColor ?? self.backgroundConfiguration?.backgroundColor
        }
    }

}
