//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
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
