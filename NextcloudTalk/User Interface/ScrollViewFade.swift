//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

extension UIScrollView {

    /// Width of the fade shown at an edge that has more content behind it
    static let horizontalFadeWidth: CGFloat = 16

    /// Fades out a horizontal edge that can be scrolled towards, so it is visible that there is more content.
    /// Call this from `layoutSubviews`, which is also run while scrolling.
    func updateHorizontalScrollFade(fadeWidth: CGFloat = UIScrollView.horizontalFadeWidth) {
        guard self.bounds.width > 0 else { return }

        let minOffset = -self.adjustedContentInset.left
        let maxOffset = self.contentSize.width + self.adjustedContentInset.right - self.bounds.width

        let canScrollToLeading = self.contentOffset.x > minOffset + 1
        let canScrollToTrailing = self.contentOffset.x < maxOffset - 1

        // Without anything to fade there's no need for a mask yet
        guard canScrollToLeading || canScrollToTrailing || self.layer.mask != nil else { return }

        let fadeLayer = self.layer.mask as? CAGradientLayer ?? {
            let gradientLayer = CAGradientLayer()
            gradientLayer.startPoint = .init(x: 0, y: 0.5)
            gradientLayer.endPoint = .init(x: 1, y: 0.5)
            self.layer.mask = gradientLayer

            return gradientLayer
        }()

        let opaque = UIColor.white.cgColor
        let clear = UIColor.clear.cgColor
        let fade = min(fadeWidth, self.bounds.width / 3) / self.bounds.width

        // Scroll views scroll by moving their bounds origin, so using the bounds here keeps the
        // mask in place while the content moves underneath it
        let colors = [canScrollToLeading ? clear : opaque, opaque, opaque, canScrollToTrailing ? clear : opaque]
        let previousColors = fadeLayer.colors as? [CGColor]

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeLayer.frame = self.bounds
        fadeLayer.colors = colors
        fadeLayer.locations = [0, NSNumber(value: fade), NSNumber(value: 1 - fade), 1]
        CATransaction.commit()

        // An edge reaching or leaving its end fades, instead of the fade popping in and out
        if let previousColors, previousColors != colors {
            let animation = CABasicAnimation(keyPath: "colors")
            animation.fromValue = fadeLayer.presentation()?.colors ?? previousColors
            animation.toValue = colors
            animation.duration = 0.2
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            fadeLayer.add(animation, forKey: "colors")
        }
    }

    /// Scrolls `view` into the visible area, keeping it clear of the fade at the edges
    func scrollToVisible(_ view: UIView, fadeWidth: CGFloat = UIScrollView.horizontalFadeWidth, animated: Bool = true) {
        let viewRect = view.convert(view.bounds, to: self)

        self.scrollRectToVisible(viewRect.insetBy(dx: -fadeWidth, dy: 0), animated: animated)
    }
}

/// Scroll view that fades out a horizontal edge that can be scrolled towards
class FadingScrollView: UIScrollView {

    override func layoutSubviews() {
        super.layoutSubviews()
        self.updateHorizontalScrollFade()
    }
}
