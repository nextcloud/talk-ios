//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SwiftUI

struct RoomNameTableViewCellWrapper: UIViewRepresentable {
    @Binding var room: NCRoom

    func makeUIView(context: Context) -> RoomNameTableViewCell {
        let cell: RoomNameTableViewCell = .fromNib()
        cell.translatesAutoresizingMaskIntoConstraints = false

        return cell
    }

    func updateUIView(_ cell: RoomNameTableViewCell, context: Context) {
        cell.roomNameTextField.text = room.name

        if room.type == .oneToOne || room.type == .formerOneToOne || room.type == .changelog {
            cell.roomNameTextField.text = room.displayName
        }

        cell.roomImage.setAvatar(for: room)

        if room.hasCall {
            cell.favoriteImage.tintColor = .systemRed
            cell.favoriteImage.image = UIImage(systemName: "video.fill")
        } else if room.isFavorite {
            cell.favoriteImage.tintColor = .systemYellow
            cell.favoriteImage.image = UIImage(systemName: "star.fill")
        }

        cell.roomNameTextField.isUserInteractionEnabled = false

        if room.canModerate || room.type == .noteToSelf {
            cell.accessoryType = .disclosureIndicator
            cell.isUserInteractionEnabled = true
        } else {
            cell.accessoryType = .none
            cell.isUserInteractionEnabled = false
        }
    }
}

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
