//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class RoomTableViewCell: UITableViewCell {

    @IBOutlet weak var roomImage: AvatarImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var unreadMessagesView: UIView!
    @IBOutlet weak var dateLabel: UILabel!
    @IBOutlet weak var favoriteImage: UIImageView!
    @IBOutlet weak var userStatusImageView: UIImageView!
    @IBOutlet weak var userStatusLabel: UILabel!
    @IBOutlet weak var unreadMessageViewWidth: NSLayoutConstraint!
    @IBOutlet weak var titleLabelTopConstraint: NSLayoutConstraint!

    public static var identifier = "RoomCellIdentifier"
    public static var nibName = "RoomTableViewCell"
    public static var cellHeight = 74.0

    public var roomToken: String?
    public var titleOnly = false {
        didSet {
            self.titleLabelTopConstraint.constant = titleOnly ? titleOnlyOriginY : titleOriginY
        }
    }

    internal var unreadMessagesBadge: RoundedNumberView?
    internal var unreadMessages: Int = 0
    internal var highlightType: HighlightType = .none

    private let titleOriginY = 12.0
    private let titleOnlyOriginY = 26.0

    public override func awakeFromNib() {
        super.awakeFromNib()

        self.roomImage.layer.cornerRadius = 24.0
        self.roomImage.layer.masksToBounds = true
        self.roomImage.backgroundColor = NCAppBranding.placeholderColor()

        self.unreadMessagesView.isHidden = true
        self.favoriteImage.contentMode = .center

        if UIView.userInterfaceLayoutDirection(for: self.dateLabel.semanticContentAttribute) == .rightToLeft {
            self.dateLabel.textAlignment = .left
        } else {
            self.dateLabel.textAlignment = .right
        }
    }

    public override func prepareForReuse() {
        super.prepareForReuse()

        // Fix problem of rendering downloaded image in a reused cell
        self.roomImage.cancelCurrentRequest()

        self.roomImage.image = nil
        self.favoriteImage.image = nil
        self.favoriteImage.tintColor = .clear
        self.subtitleLabel.text = ""
        self.dateLabel.text = ""

        self.userStatusImageView.image = nil
        self.userStatusImageView.backgroundColor = .clear

        self.userStatusLabel.isHidden = true

        self.titleLabelTopConstraint.constant = titleOriginY

        self.unreadMessagesView.isHidden = true
        self.unreadMessagesBadge = nil

        self.unreadMessagesView.subviews.forEach { $0.removeFromSuperview() }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        // TODO: Should this be in layoutSubviews?
        if self.unreadMessagesBadge == nil {
            let badge = RoundedNumberView()
            self.unreadMessagesBadge = badge

            badge.highlightType = self.highlightType
            badge.number = self.unreadMessages

            self.unreadMessageViewWidth.constant = self.unreadMessages > 0 ? badge.frame.size.width : 0
            self.unreadMessagesView.addSubview(badge)
        }
    }

    public override func setSelected(_ selected: Bool, animated: Bool) {
        // Ignore deselection if this is the cell for the currently selected room
        // E.g. prevent automatic deselection when bringing up swipe actions of cell
        if !selected, NCUserInterfaceController.sharedInstance().roomsTableViewController.selectedRoomToken == self.roomToken {
            return
        }

        super.setSelected(selected, animated: animated)
    }

    public func setUnread(messages number: Int, mentioned: Bool, groupMentioned: Bool) {
        self.unreadMessages = number

        if number > 0 {
            self.titleLabel.font = UIFont.preferredFont(for: .headline, weight: .bold)
            self.subtitleLabel.font = UIFont.preferredFont(for: .callout, weight: .bold)
            self.dateLabel.font = UIFont.preferredFont(for: .footnote, weight: .semibold)
            self.unreadMessagesView.isHidden = false
        } else {
            self.titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
            self.subtitleLabel.font = UIFont.preferredFont(forTextStyle: .callout)
            self.dateLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
            self.unreadMessagesView.isHidden = true
        }

        self.highlightType = .none

        if groupMentioned {
            self.highlightType = .border
        }

        if mentioned {
            self.highlightType = .important
        }
    }

    public func setUserStatusIcon(_ userStatusIcon: String) {
        self.userStatusLabel.text = userStatusIcon
        self.userStatusLabel.isHidden = false
    }

    public func setUserStatusIconWithImage(_ image: UIImage) {
        self.userStatusImageView.image = image
        self.userStatusImageView.contentMode = .center
        self.userStatusImageView.layer.cornerRadius = 10
        self.userStatusImageView.clipsToBounds = true

        // When a background color is set directly to the cell it seems that there is no background configuration.
        self.userStatusImageView.backgroundColor = self.backgroundConfiguration?.backgroundColor ?? self.backgroundColor
    }

    public func setUserStatus(_ userStatus: String) {
        var statusImage: UIImage?

        if userStatus == "online" {
            statusImage = UIImage(named: "user-status-online")
        } else if userStatus == "away" {
            statusImage = UIImage(named: "user-status-away")
        } else if userStatus == "dnd" {
            statusImage = UIImage(named: "user-status-dnd")
        }

        if let statusImage {
            self.setUserStatusIconWithImage(statusImage)
        }
    }
}
