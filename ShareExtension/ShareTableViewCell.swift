//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

// The xib references the class without a module
@objc(ShareTableViewCell)
class ShareTableViewCell: UITableViewCell {

    @objc static let identifier = "ShareCellIdentifier"
    @objc static let nibName = "ShareTableViewCell"
    @objc static let cellHeight: CGFloat = 56.0

    @IBOutlet weak var avatarImageView: AvatarImageView!
    @IBOutlet weak var titleLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()

        avatarImageView.layer.cornerRadius = 18.0
        avatarImageView.layer.masksToBounds = true
        avatarImageView.backgroundColor = NCAppBranding.placeholderColor()
        avatarImageView.contentMode = .center
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        // Fix problem of rendering downloaded image in a reused cell
        avatarImageView.prepareForReuse()
        titleLabel.text = ""
    }
}
