//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

class RoomInvitationViewCell: UITableViewCell {

    @objc public static var NibName = "RoomInvitationViewCell"
    @objc public static var ReuseIdentifier = "RoomInvitationViewCellIdentifier"
    @objc public static var CellHeight = 65.0

    @IBOutlet weak var detailsLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()

        self.selectionStyle = .none
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        self.detailsLabel.text = ""
    }
}
