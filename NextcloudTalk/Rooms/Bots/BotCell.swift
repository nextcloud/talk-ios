//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

protocol BotCellDelegate: AnyObject {
    func changeBotState(_ cell: BotCell, bot: Bot)
}

class BotCell: UITableViewCell {

    public static let identifier = "BotCell"

    public weak var delegate: BotCellDelegate?

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var detailsLabel: UILabel!
    @IBOutlet weak var enableButton: NCButton!

    private var bot: Bot?

    override func awakeFromNib() {
        super.awakeFromNib()

        self.selectionStyle = .none
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        self.titleLabel.text = ""
        self.detailsLabel.text = ""
        self.bot = nil

        self.setEnabledState()
    }

    public func setupFor(bot: Bot) {
        self.bot = bot

        self.titleLabel.text = bot.name
        self.detailsLabel.text = bot.description

        self.enableButton.isEnabled = true
        self.enableButton.setButtonStyle(style: .primary)
        self.enableButton.setButtonAction(target: self, selector: #selector(changeBotStatePressed))

        switch bot.state {
        case .disabled:
            self.enableButton.setTitle(NSLocalizedString("Enable", comment: ""), for: .normal)
            self.enableButton.setButtonStyle(style: .secondary)
        case .enabled:
            self.enableButton.setTitle(NSLocalizedString("Disable", comment: ""), for: .normal)
        case .noSetup:
            self.enableButton.setTitle(NSLocalizedString("Enabled", comment: ""), for: .normal)
            self.enableButton.isEnabled = false
        default:
            self.enableButton.setTitle(NSLocalizedString("Unknown", comment: ""), for: .normal)
            self.enableButton.isEnabled = false
        }
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
    func changeBotStatePressed() {
        guard let bot else { return }

        self.delegate?.changeBotState(self, bot: bot)
    }
}
