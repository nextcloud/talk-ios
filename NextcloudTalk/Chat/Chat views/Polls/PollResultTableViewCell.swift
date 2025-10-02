//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

class PollResultTableViewCell: UITableViewCell {

    @IBOutlet weak var optionLabel: UILabel!
    @IBOutlet weak var optionProgressView: UIProgressView!
    @IBOutlet weak var resultLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        optionProgressView.progressTintColor = NCAppBranding.elementColor()
    }

    override func prepareForReuse() {
        optionLabel.font = UIFont.systemFont(ofSize: 17, weight: .regular)
        resultLabel.font = UIFont.systemFont(ofSize: 17, weight: .regular)
    }

    func highlightResult() {
        optionLabel.font = UIFont.systemFont(ofSize: 17, weight: .bold)
        resultLabel.font = UIFont.systemFont(ofSize: 17, weight: .bold)
    }
}
