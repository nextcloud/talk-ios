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

class AccountTableViewCell: UITableViewCell {

    @IBOutlet weak var accountImageView: UIImageView!
    @IBOutlet weak var accountNameLabel: UILabel!
    @IBOutlet weak var accountServerLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        self.accountImageView.layer.cornerRadius = 15.0
        self.accountImageView.layer.masksToBounds = true
        self.separatorInset = UIEdgeInsets(top: 0, left: 54, bottom: 0, right: 0)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.accountImageView.image = nil
        self.accountNameLabel.text = ""
        self.accountServerLabel.text = ""
    }

}
