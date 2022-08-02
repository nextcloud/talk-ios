//
// Copyright (c) 2022 Ivan Sein <ivan@nextcloud.com>
//
// Author Ivan Sein <ivan@nextcloud.com>
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

import UIKit

class PollFooterView: UIView {

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var primaryButtonContainerView: UIView!
    @IBOutlet weak var secondaryButtonContainerView: UIView!
    @IBOutlet weak var primaryButton: UIButton!
    @IBOutlet weak var secondaryButton: UIButton!

    static let heightForOption: CGFloat = 60 // buttonHeight(40) + 20 padding
    var primaryButtonAction: Selector?
    var secondaryButtonAction: Selector?

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

        primaryButton.setTitleColor(NCAppBranding.themeTextColor(), for: .normal)
        primaryButton.setTitleColor(NCAppBranding.themeTextColor().withAlphaComponent(0.5), for: .disabled)
        primaryButton.layer.cornerRadius = 20.0
        primaryButton.layer.masksToBounds = true
        primaryButton.backgroundColor = NCAppBranding.themeColor()

        secondaryButton.setTitleColor(NCAppBranding.elementColor(), for: .normal)
        secondaryButton.setTitleColor(NCAppBranding.elementColor().withAlphaComponent(0.5), for: .disabled)
        secondaryButton.layer.cornerRadius = 20.0
        secondaryButton.layer.masksToBounds = true
        secondaryButton.layer.borderColor = NCAppBranding.placeholderColor().cgColor
        secondaryButton.layer.borderWidth = 1.0
    }

    func setPrimaryButtonAction(target: Any?, selector: Selector) {
        primaryButton.removeTarget(target, action: primaryButtonAction, for: .touchUpInside)
        primaryButton.addTarget(target, action: selector, for: .touchUpInside)
        primaryButtonAction = selector
    }

    func setSecondaryButtonAction(target: Any?, selector: Selector) {
        secondaryButton.removeTarget(target, action: secondaryButtonAction, for: .touchUpInside)
        secondaryButton.addTarget(target, action: selector, for: .touchUpInside)
        secondaryButtonAction = selector
    }
}
