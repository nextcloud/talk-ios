//
// Copyright (c) 2022 Aleksandra Lazarevic <aleksandra@nextcloud.com>
//
// Author Aleksandra Lazarevic <aleksandra@nextcloud.com>
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

import UIKit
import NextcloudKit

class UserSettingsTableViewCell: UITableViewCell {

    @IBOutlet weak var userImageView: UIImageView!
    @IBOutlet weak var userDisplayNameLabel: UILabel!
    @IBOutlet weak var userStatusImageView: UIImageView!
    @IBOutlet weak var serverAddressLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        self.userImageView.layer.cornerRadius = 40.0
        self.userImageView.layer.masksToBounds = true
    }

}
