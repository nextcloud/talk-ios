//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

class PollFooterView: UIView {

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var primaryButtonContainerView: UIView!
    @IBOutlet weak var secondaryButtonContainerView: UIView!
    @IBOutlet weak var primaryButton: NCButton!
    @IBOutlet weak var secondaryButton: NCButton!

    static let heightForOption: CGFloat = 60 // buttonHeight(40) + 20 padding

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    func commonInit() {
        Bundle.main.loadNibNamed("PollFooterView", owner: self, options: nil)
        contentView.frame = self.bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.addSubview(contentView)
    }
}
