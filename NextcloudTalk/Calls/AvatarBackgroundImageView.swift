//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

class GradientView: UIView {

    override class var layerClass: AnyClass {
        return CAGradientLayer.self
    }

    // Swift can't narrow the inherited `layer` type the way the ObjC @dynamic declaration did
    var gradientLayer: CAGradientLayer {
        // swiftlint:disable:next force_cast
        return self.layer as! CAGradientLayer
    }
}

@objcMembers class AvatarBackgroundImageView: UIImageView {

    var gradientView: GradientView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        initGradientLayer()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        initGradientLayer()
    }

    private func initGradientLayer() {
        let gradientView = GradientView(frame: self.bounds)
        gradientView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        gradientView.gradientLayer.colors = [UIColor(white: 0, alpha: 0.6).cgColor,
                                             UIColor(white: 0, alpha: 0.6).cgColor]
        gradientView.gradientLayer.locations = [0.0, 1.0]

        self.addSubview(gradientView)
        self.gradientView = gradientView
    }
}
