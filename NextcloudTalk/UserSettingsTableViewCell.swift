//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import NextcloudKit

class UserSettingsTableViewCell: UITableViewCell {

    @IBOutlet weak var userImageView: UIImageView!
    @IBOutlet weak var userDisplayNameLabel: UILabel!
    @IBOutlet weak var serverAddressLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        self.userImageView.layer.cornerRadius = 40.0
        self.userImageView.layer.masksToBounds = true
    }

}
