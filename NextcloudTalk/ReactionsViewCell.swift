/**
 * @copyright Copyright (c) 2022 Ivan Sein <ivan@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
 *
 * @license GNU GPL version 3 or any later version
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

import UIKit

@objcMembers class ReactionsViewCell: UICollectionViewCell {

    @IBOutlet weak var label: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        label.layer.borderWidth = 1.0
        label.layer.borderColor = UIColor.lightGray.cgColor
        if #available(iOS 13.0, *) {
            label.layer.borderColor = UIColor.tertiaryLabel.cgColor
        }
        label.layer.cornerRadius = 15.0
        label.clipsToBounds = true
        label.backgroundColor = NCAppBranding.backgroundColor()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        label.text = ""
    }

    func setReaction(reaction: NCChatReaction) {
        label.text = reaction.reaction + " " + String(reaction.count)
    }

}
