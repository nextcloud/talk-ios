//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class RoomNameTableViewCell: UITableViewCell {

    @IBOutlet weak var roomImage: AvatarImageView!
    @IBOutlet weak var favoriteImage: UIImageView!
    @IBOutlet weak var roomNameTextField: UITextField!

    public static var identifier = "RoomNameCellIdentifier"
    public static var nibName = "RoomNameTableViewCell"

    public override func awakeFromNib() {
        super.awakeFromNib()

        self.roomImage.layer.cornerRadius = 24.0
        self.roomImage.layer.masksToBounds = true
        self.roomImage.backgroundColor = NCAppBranding.placeholderColor()
        self.roomImage.contentMode = .scaleToFill

        self.favoriteImage.contentMode = .center

        self.roomNameTextField.placeholder = NSLocalizedString("Conversation name", comment: "")
    }

    public override func prepareForReuse() {
        super.prepareForReuse()

        self.roomImage.image = nil
        self.roomImage.contentMode = .center
        self.favoriteImage.image = nil
        self.favoriteImage.tintColor = .clear
    }
}
