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
        optionLabel.font = .preferredFont(for: .body, weight: .regular)
        resultLabel.font = .preferredFont(for: .body, weight: .regular)
    }

    func highlightResult() {
        optionLabel.font = .preferredFont(for: .body, weight: .bold)
        resultLabel.font = .preferredFont(for: .body, weight: .bold)
    }
}
