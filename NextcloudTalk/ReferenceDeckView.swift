//
// Copyright (c) 2022 Marcel Müller <marcel-mueller@gmx.de>
//
// Author Marcel Müller <marcel-mueller@gmx.de>
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

import Foundation

@objcMembers class ReferenceDeckView: UIView {

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var referenceTypeIcon: UIImageView!
    @IBOutlet weak var referenceTitle: UILabel!
    @IBOutlet weak var referenceDescription: UITextView!
    @IBOutlet weak var referenceDueDate: UILabel!
    @IBOutlet weak var referenceDueDateIcon: UIImageView!

    var url: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    func commonInit() {
        Bundle.main.loadNibNamed("ReferenceDeckView", owner: self, options: nil)
        contentView.frame = self.bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        referenceTitle.text = ""
        referenceDescription.text = ""
        referenceDueDate.text = ""
        referenceTypeIcon.image = nil

        // Remove padding from textView and adjust lineBreakMode
        referenceDescription.textContainerInset = .zero
        referenceDescription.textContainer.lineFragmentPadding = .zero
        referenceDescription.textContainer.lineBreakMode = .byTruncatingTail

        let tap = UITapGestureRecognizer(target: self, action: #selector(self.handleTap))
        contentView.addGestureRecognizer(tap)

        self.addSubview(contentView)
    }

    func handleTap() {
        if let url = url {
            NCUtils.openLink(inBrowser: url)
        }
    }

    func update(for sharedDeckCard: NCDeckCardParameter) {
        referenceTypeIcon.image = UIImage(named: "deck-item")

        self.url = sharedDeckCard.link
        referenceTitle.text = sharedDeckCard.name ?? ""
        referenceDescription.isHidden = true
        referenceDueDate.isHidden = true
        referenceDueDateIcon.isHidden = true
    }

    func update(for reference: [String: AnyObject], and url: String) {
        self.url = url

        referenceTypeIcon.image = UIImage(named: "deck-item")

        guard let card = reference["card"] as? [String: AnyObject] else {
            referenceTitle.text = url
            referenceDescription.isHidden = true
            referenceDueDate.isHidden = true
            referenceDueDateIcon.isHidden = true
            return
        }

        if let dueDateString = card["duedate"] as? String {

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

            if let date = dateFormatter.date(from: dueDateString) {
                referenceDueDate.text = NCUtils.readableDateTime(from: date)
            }

            // Date format was fixed in https://github.com/nextcloud/deck/pull/4115
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"

            if let date = dateFormatter.date(from: dueDateString) {
                referenceDueDate.text = NCUtils.readableDateTime(from: date)
            }

        } else {
            referenceDueDate.isHidden = true
            referenceDueDateIcon.isHidden = true
        }

        if let title = card["title"] as? String {
            referenceTitle.text = title
        }

        if let body = card["description"] as? String {
            referenceDescription.text = body
        } else {
            referenceDescription.text = NSLocalizedString("No description provided", comment: "")
        }
    }
}
