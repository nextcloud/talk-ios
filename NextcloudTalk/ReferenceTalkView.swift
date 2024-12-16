//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SwiftyAttributes

@objcMembers class ReferenceTalkView: UIView {

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var referenceTypeIcon: AvatarImageView!
    @IBOutlet weak var referenceTitle: UILabel!
    @IBOutlet weak var referenceBody: UITextView!

    var url: String?
    var roomToken: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    func commonInit() {
        Bundle.main.loadNibNamed("ReferenceTalkView", owner: self, options: nil)
        contentView.frame = self.bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        referenceTitle.text = ""
        referenceBody.text = ""
        referenceTypeIcon.image = nil

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
        if let roomToken = self.roomToken {
            NCRoomsManager.sharedInstance().startChat(withRoomToken: roomToken)
        } else if let url = url {
            NCUtils.openLinkInBrowser(link: url)
        }
    }

    func update(for reference: [String: AnyObject], and openGraph: [String: String?], and url: String) {
        self.url = url

        if let description = openGraph["description"] as? String {
            self.referenceBody.text = description
        } else {
            self.referenceBody.text = ""
        }

        if let title = reference["name"] as? String {
            self.referenceTitle.text = title
        } else {
            self.referenceTitle.text = ""
        }

        if let roomToken = reference["id"] as? String {
            self.roomToken = roomToken

            let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
            let room = NCDatabaseManager.sharedInstance().room(withToken: roomToken, forAccountId: activeAccount.accountId)

            if let room {
                self.referenceTypeIcon.setAvatar(for: room)
                self.referenceTypeIcon.layer.cornerRadius = self.referenceTypeIcon.frame.height / 2
            } else {
                self.referenceTypeIcon.layer.cornerRadius = 0
                self.referenceTypeIcon.image = UIImage(named: "talk-20")?.withTintColor(.systemGray, renderingMode: .alwaysOriginal)
            }
        }
    }
}
