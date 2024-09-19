//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers class ReferenceGiphyView: UIView {

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var referenceThumbnailView: UIImageView!
    @IBOutlet weak var referenceName: UILabel!
    @IBOutlet weak var referenceDescription: UITextView!
    @IBOutlet weak var referenceLink: UILabel!

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
        Bundle.main.loadNibNamed("ReferenceDefaultView", owner: self, options: nil)
        contentView.frame = self.bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        referenceName.text = ""
        referenceDescription.text = ""
        referenceLink.text = ""

        // Remove padding from textView
        referenceDescription.textContainerInset = .zero
        referenceDescription.textContainer.lineFragmentPadding = .zero

        referenceThumbnailView.layer.cornerRadius = 8.0
        referenceThumbnailView.layer.masksToBounds = true

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

        referenceName.text = reference["title"] as? String ?? ""
        referenceDescription.text = reference["alt_text"] as? String ?? ""
        referenceLink.text = url

        if referenceDescription.text.isEmpty {
            referenceDescription.isHidden = true
        }

        if let proxiedUrlString = reference["proxied_url"] as? String, let proxiedUrl = URL(string: proxiedUrlString) {
            referenceThumbnailView.setGifFromURL(proxiedUrl)
        } else {
            setPlaceholderThumbnail()
        }
    }

    func setPlaceholderThumbnail() {
        referenceThumbnailView.image = UIImage(systemName: "safari")?.withTintColor(UIColor.secondarySystemFill, renderingMode: .alwaysOriginal)
    }
}
