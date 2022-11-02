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

@objcMembers class ReferenceDefaultView: UIView {

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
            NCUtils.openLink(inBrowser: url)
        }
    }

    func update(for reference: [String: String?]?, and url: String) {
        self.url = url

        guard let reference = reference else {
            referenceName.isHidden = true
            referenceDescription.isHidden = true
            referenceLink.text = url

            setPlaceholderThumbnail()
            return
        }

        referenceName.text = reference["name"] ?? ""
        referenceDescription.text = reference["description"] ?? ""
        referenceLink.text = reference["link"] ?? ""

        if referenceDescription.text.isEmpty {
            referenceDescription.isHidden = true
        }

        if let thumbUrlString = reference["thumb"] as? String,
           let request = NCAPIController.sharedInstance().createReferenceThumbnailRequest(forUrl: thumbUrlString) {

            referenceThumbnailView.setImageWith(request, placeholderImage: nil, success: nil) { _, _, _ in
                self.setPlaceholderThumbnail()
            }
        } else {
            setPlaceholderThumbnail()
        }
    }

    func setPlaceholderThumbnail() {
        referenceThumbnailView.image = UIImage(systemName: "safari")?.withTintColor(UIColor.secondarySystemFill, renderingMode: .alwaysOriginal)
    }
}
