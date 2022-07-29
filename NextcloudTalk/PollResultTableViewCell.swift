//
// Copyright (c) 2022 Ivan Sein <ivan@nextcloud.com>
//
// Author Ivan Sein <ivan@nextcloud.com>
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
