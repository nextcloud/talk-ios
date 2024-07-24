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

        self.titleLabel.text = bannedActor.bannedDisplayName ?? "Unknown"

        var bannedDate = ""

        if let time = bannedActor.bannedTime {
            bannedDate = NCUtils.readableDateTime(fromDate: Date(timeIntervalSince1970: TimeInterval(time)))
        }

        let bannedByLabel = NSLocalizedString("Banned by:", comment: "Date and time of ban creation")
        let bannedDateLabel = NSLocalizedString("Date:", comment: "name of a moderator who banned a participant")
        let bannedNoteLabel = NSLocalizedString("Note:", comment: "Internal note for moderators, usually a reason for this ban")

        var details = NSMutableAttributedString()
        let attributedNewLine = NSAttributedString(string: "\n")

        details.append(bannedByLabel.withFont(.preferredFont(for: .caption1, weight: .bold)))
        details.append(" \(bannedActor.bannedDisplayName ?? NSLocalizedString("Unknown", comment: ""))".withFont(.preferredFont(forTextStyle: .caption1)))
        details.append(attributedNewLine)
        details.append(bannedDateLabel.withFont(.preferredFont(for: .caption1, weight: .bold)))
        details.append(" \(bannedDate)".withFont(.preferredFont(forTextStyle: .caption1)))

        if let internalNote = bannedActor.internalNote, !internalNote.isEmpty {
            details.append(attributedNewLine)
            details.append(bannedNoteLabel.withFont(.preferredFont(for: .caption1, weight: .bold)))
            details.append(" \(internalNote)".withFont(.preferredFont(forTextStyle: .caption1)))
        }

        self.detailsLabel.attributedText = details

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
