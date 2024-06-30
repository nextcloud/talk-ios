//
// Copyright (c) 2024 Marcel Müller <marcel-mueller@gmx.de>
//
// Author Marcel Müller <marcel-mueller@gmx.de>
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

protocol BannedActorCellDelegate: AnyObject {
    func bannedActorCellUnbanActor(_ cell: BannedActorCell, bannedActor: BannedActor)
}

class BannedActorCell: UITableViewCell {

    public weak var delegate: BannedActorCellDelegate?

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var detailsLabel: UILabel!
    @IBOutlet weak var unbanButton: NCButton!

    private var bannedActor: BannedActor?

    override func awakeFromNib() {
        super.awakeFromNib()

        self.selectionStyle = .none
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        self.titleLabel.text = ""
        self.detailsLabel.text = ""
        self.bannedActor = nil

        self.setEnabledState()
    }

    public func setupFor(bannedActor: BannedActor) {
        self.bannedActor = bannedActor

        self.titleLabel.text = bannedActor.bannedId ?? "Unknown"

        var bannedTime = ""

        if let time = bannedActor.bannedTime {
            bannedTime = NCUtils.readableDateTime(fromDate: Date(timeIntervalSince1970: TimeInterval(time)))
        }

        var details = "\(bannedTime)"
        details = "\(details)\n\(bannedActor.actorId ?? "Unknown")"
        details = "\(details)\n\(bannedActor.internalNote ?? "")"

        self.detailsLabel.text = details

        self.unbanButton.setTitle(NSLocalizedString("Unban", comment: ""), for: .normal)
        self.unbanButton.setButtonStyle(style: .primary)
        self.unbanButton.setButtonAction(target: self, selector: #selector(unbanButtonPressed))
    }

    public func setDisabledState() {
        self.contentView.isUserInteractionEnabled = false
        self.contentView.alpha = 0.5
    }

    public func setEnabledState() {
        self.contentView.isUserInteractionEnabled = true
        self.contentView.alpha = 1
    }

    @objc
    func unbanButtonPressed() {
        if let bannedActor {
            self.delegate?.bannedActorCellUnbanActor(self, bannedActor: bannedActor)
        }
    }
}
