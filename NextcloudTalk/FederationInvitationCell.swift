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

protocol FederationInvitationCellDelegate: AnyObject {
    func federationInvitationCellAccept(_ cell: FederationInvitationCell, invitation: FederationInvitation)
    func federationInvitationCellReject(_ cell: FederationInvitationCell, invitation: FederationInvitation)
}

class FederationInvitationCell: UITableViewCell {

    public weak var delegate: FederationInvitationCellDelegate?

    @IBOutlet weak var conversationNameLabel: UILabel!
    @IBOutlet weak var detailsLabel: UILabel!
    @IBOutlet weak var rejectButton: NCButton!
    @IBOutlet weak var acceptButton: NCButton!

    private var federationInvitation: FederationInvitation?

    override func awakeFromNib() {
        super.awakeFromNib()

        self.selectionStyle = .none
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        self.conversationNameLabel.text = ""
        self.detailsLabel.text = ""
        self.federationInvitation = nil

        self.setEnabledState()
    }

    public func setupForInvitation(invitation: FederationInvitation) {
        self.federationInvitation = invitation

        self.conversationNameLabel.text = invitation.remoteConversationName ?? ""
        self.detailsLabel.text = String(format: NSLocalizedString("from %@ at %@", comment: "from Alice at nextcloud.local"),
                                        invitation.inviterDisplayName ?? NSLocalizedString("Unknown", comment: ""),
                                        invitation.remoteServer ?? NSLocalizedString("Unknown", comment: ""))

        self.acceptButton.setTitle(NSLocalizedString("Accept", comment: ""), for: .normal)
        self.rejectButton.setTitle(NSLocalizedString("Reject", comment: ""), for: .normal)
        self.acceptButton.setButtonStyle(style: .primary)
        self.rejectButton.setButtonStyle(style: .secondary)

        self.acceptButton.setButtonAction(target: self, selector: #selector(acceptButtonPressed))
        self.rejectButton.setButtonAction(target: self, selector: #selector(rejectButtonPressed))
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
    func acceptButtonPressed() {
        if let federationInvitation {
            self.delegate?.federationInvitationCellAccept(self, invitation: federationInvitation)
        }
    }

    @objc
    func rejectButtonPressed() {
        if let federationInvitation {
            self.delegate?.federationInvitationCellReject(self, invitation: federationInvitation)
        }
    }
}
