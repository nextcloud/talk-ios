//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

@objcMembers class PlaceholderView: UIView {

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var placeholderView: UIView!
    @IBOutlet weak var placeholderImage: UIImageView!
    @IBOutlet weak var placeholderTextView: UITextView!
    @IBOutlet weak var loadingView: UIActivityIndicatorView!

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    // The style is unused, kept because every call site passes one
    convenience init(for style: UITableView.Style) {
        self.init(frame: .zero)
    }

    private func commonInit() {
        Bundle.main.loadNibNamed("PlaceholderView", owner: self, options: nil)

        self.addSubview(self.contentView)

        self.contentView.frame = self.bounds
    }

    func setImage(_ image: UIImage?) {
        self.placeholderImage.image = image?.withRenderingMode(.alwaysTemplate)
        self.placeholderImage.contentMode = .scaleAspectFit
        self.placeholderImage.tintColor = NCAppBranding.placeholderColor()
    }
}
