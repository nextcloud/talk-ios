//
// Copyright (c) 2024 Marcel Müller <marcel.mueller@nextcloud.com>
//
// Author Ivan Sein <ivan@nextcloud.com>
// Author Marcel Müller <marcel.mueller@nextcloud.com>
//
// GNU GPL version 3 or any later version
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
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
