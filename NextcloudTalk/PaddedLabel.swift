//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

class PaddedLabel: UILabel {
    static let textInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)

    override func drawText(in rect: CGRect) {
        let insetRect = rect.inset(by: PaddedLabel.textInsets)
        super.drawText(in: insetRect)
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + PaddedLabel.textInsets.left + PaddedLabel.textInsets.right,
                      height: size.height + PaddedLabel.textInsets.top + PaddedLabel.textInsets.bottom)
    }
}
