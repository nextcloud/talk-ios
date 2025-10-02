//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
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
            NCUtils.openLinkInBrowser(link: url)
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
                referenceDueDate.text = NCUtils.readableDateTime(fromDate: date)
            }

            // Date format was fixed in https://github.com/nextcloud/deck/pull/4115
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"

            if let date = dateFormatter.date(from: dueDateString) {
                referenceDueDate.text = NCUtils.readableDateTime(fromDate: date)
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
