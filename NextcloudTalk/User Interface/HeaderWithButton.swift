//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

@objcMembers class HeaderWithButton: UIView {

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var label: UILabel!
    @IBOutlet weak var button: UIButton!

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    private func commonInit() {
        Bundle.main.loadNibNamed("HeaderWithButton", owner: self, options: nil)

        self.label.textColor = .secondaryLabel

        self.addSubview(self.contentView)

        if UIView.userInterfaceLayoutDirection(for: self.label.semanticContentAttribute) == .rightToLeft {
            self.label.textAlignment = .right
            self.button.contentHorizontalAlignment = .left
        } else {
            self.label.textAlignment = .left
            self.button.contentHorizontalAlignment = .right
        }

        self.contentView.frame = self.bounds
    }
}
