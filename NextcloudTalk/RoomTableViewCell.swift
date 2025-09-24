//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class RoomTableViewCell: UITableViewCell {

    @IBOutlet weak var containerView: UIView!
    @IBOutlet weak var avatarView: AvatarView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var unreadMessagesView: BadgeView!
    @IBOutlet weak var dateLabel: UILabel!

    public static var identifier = "RoomCellIdentifier"
    public static var nibName = "RoomTableViewCell"

    public var roomToken: String?
    public var titleOnly = false {
        didSet {
            self.subtitleLabel.isHidden = self.titleOnly
        }
    }

    public override func awakeFromNib() {
        super.awakeFromNib()

        if UIView.userInterfaceLayoutDirection(for: self.dateLabel.semanticContentAttribute) == .rightToLeft {
            self.dateLabel.textAlignment = .left
        } else {
            self.dateLabel.textAlignment = .right
        }

        self.containerView.layer.cornerRadius = 8
        self.containerView.layer.masksToBounds = true
        self.selectionStyle = .none
    }

    public override func prepareForReuse() {
        super.prepareForReuse()

        self.avatarView.prepareForReuse()

        self.subtitleLabel.text = ""
        self.dateLabel.text = ""
        self.titleOnly = false

        self.unreadMessagesView.setBadgeNumber(0)
    }

    public override func setSelected(_ selected: Bool, animated: Bool) {
        // Ignore deselection if this is the cell for the currently selected room
        // E.g. prevent automatic deselection when bringing up swipe actions of cell
        if !selected, NCUserInterfaceController.sharedInstance().roomsTableViewController.selectedRoomToken == self.roomToken {
            return
        }

        if selected {
            self.containerView.backgroundColor = NCAppBranding.elementColorBackground()
        } else {
            self.containerView.backgroundColor = .clear
        }
    }

    public func setUnread(messages number: Int, mentioned: Bool, groupMentioned: Bool) {
        self.unreadMessagesView.badgeColor = NCAppBranding.themeColor()
        self.unreadMessagesView.badgeTextColor = NCAppBranding.themeTextColor()

        if mentioned {
            self.unreadMessagesView.badgeHighlightStyle = .important
        } else if groupMentioned {
            self.unreadMessagesView.badgeHighlightStyle = .border
        } else if number > 0 {
            self.unreadMessagesView.badgeHighlightStyle = .none
        }

        self.unreadMessagesView.setBadgeNumber(number)

        if number > 0 {
            self.titleLabel.font = UIFont.preferredFont(for: .headline, weight: .bold)
            self.subtitleLabel.font = UIFont.preferredFont(for: .callout, weight: .bold)
            self.dateLabel.font = UIFont.preferredFont(for: .footnote, weight: .semibold)
        } else {
            self.titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
            self.subtitleLabel.font = UIFont.preferredFont(forTextStyle: .callout)
            self.dateLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        }
    }
}
