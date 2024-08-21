//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers class ReferenceZammadView: UIView {

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var referenceTypeIcon: UIImageView!
    @IBOutlet weak var referenceTitle: UILabel!
    @IBOutlet weak var referenceBody: UITextView!
    @IBOutlet weak var referenceCommentCount: UILabel!
    @IBOutlet weak var referenceCommentIcon: UIImageView!

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
        Bundle.main.loadNibNamed("ReferenceZammadView", owner: self, options: nil)
        contentView.frame = self.bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        referenceTitle.text = ""
        referenceBody.text = ""

        // Remove padding from textView and adjust lineBreakMode
        referenceBody.textContainerInset = .zero
        referenceBody.textContainer.lineFragmentPadding = .zero
        referenceBody.textContainer.lineBreakMode = .byTruncatingTail
        referenceBody.textContainer.maximumNumberOfLines = 3

        let tap = UITapGestureRecognizer(target: self, action: #selector(self.handleTap))
        contentView.addGestureRecognizer(tap)

        self.addSubview(contentView)
    }

    func handleTap() {
        if let url = url {
            NCUtils.openLinkInBrowser(link: url)
        }
    }

    func update(for reference: [String: AnyObject], and url: String) {
        self.url = url

        if reference["error"] != nil {
            referenceTitle.text = NSLocalizedString("Zammad API error", comment: "'Zammad' is a product name")

            if let error = reference["error"] as? String, !error.isEmpty {
                referenceBody.text = error
            } else {
                referenceBody.text = NSLocalizedString("Unknown error", comment: "")
            }

            referenceCommentCount.isHidden = true
            referenceCommentIcon.isHidden = true

            return
        }

        referenceCommentCount.isHidden = false
        referenceCommentIcon.isHidden = false

        if let comments = reference["article_count"] as? Int {
            referenceCommentCount.text = String(comments)
        } else {
            referenceCommentCount.text = "0"
        }

        if let title = reference["title"] as? String {
            referenceTitle.text = title
        }

        if let ticketNumber = reference["number"] as? String, let severity = reference["severity"] as? String,
           let authorOrg = reference["zammad_ticket_author_organization"] as? [AnyHashable: Any], let authorName = authorOrg["name"] as? String {

            // Make sure we truncate each body line individually
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byTruncatingTail

            var bodyText = "#\(ticketNumber) [\(severity)]: \(authorName)".withParagraphStyle(paragraphStyle)

            // When we are able to determine the ticket state -> add that to the body
            if let zammadStates = reference["zammad_ticket_states"] as? [[AnyHashable: Any]], let ticketState = reference["state_id"] as? Int,
               let zammadState = zammadStates.first(where: { $0["id"] as? Int == ticketState }), let stateName = zammadState["name"] as? String {

                bodyText.append("\n\(stateName)".withParagraphStyle(paragraphStyle))
            }

            bodyText = bodyText.withFont(referenceBody.font ?? .preferredFont(forTextStyle: .callout)).withTextColor(referenceBody.textColor ?? .secondaryLabel)

            referenceBody.attributedText = bodyText
        } else {
            referenceBody.text = NSLocalizedString("No description provided", comment: "")
        }
    }
}
