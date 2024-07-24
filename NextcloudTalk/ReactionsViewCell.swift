//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

@objcMembers class ReactionsViewCell: UICollectionViewCell {

    @IBOutlet weak var label: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        label.layer.borderWidth = 1.0
        label.layer.borderColor = self.borderColor()
        label.layer.cornerRadius = 15.0
        label.clipsToBounds = true
        label.backgroundColor = NCAppBranding.backgroundColor()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        label.text = ""
        label.layer.borderColor = self.borderColor()
        label.backgroundColor = NCAppBranding.backgroundColor()
    }

    func borderColor() -> CGColor {
        return UIColor.tertiaryLabel.cgColor
    }

    func sizeForReaction(reaction: NCChatReaction) -> CGSize {
        let text = textForReaction(reaction: reaction)
        var size = CGSize(width: text.width(withConstrainedHeight: 30, font: .systemFont(ofSize: 13.0)), height: 30)
        size.width += 20
        return size
    }

    func textForReaction(reaction: NCChatReaction) -> String {
        return reaction.reaction + " " + String(reaction.count)
    }

    func setReaction(reaction: NCChatReaction) {
        label.text = textForReaction(reaction: reaction)
        label.backgroundColor = reaction.userReacted ? NCAppBranding.elementColor().withAlphaComponent(0.15) : NCAppBranding.backgroundColor()
        label.layer.borderColor = reaction.userReacted ? NCAppBranding.elementColor().cgColor : self.borderColor()
    }

}

extension String {
    func height(withConstrainedWidth width: CGFloat, font: UIFont) -> CGFloat {
        let constraintRect = CGSize(width: width, height: .greatestFiniteMagnitude)
        let boundingBox = self.boundingRect(with: constraintRect, options: .usesLineFragmentOrigin, attributes: [.font: font], context: nil)
        return ceil(boundingBox.height)
    }

    func width(withConstrainedHeight height: CGFloat, font: UIFont) -> CGFloat {
        let constraintRect = CGSize(width: .greatestFiniteMagnitude, height: height)
        let boundingBox = self.boundingRect(with: constraintRect, options: .usesLineFragmentOrigin, attributes: [.font: font], context: nil)
        return ceil(boundingBox.width)
    }
}
