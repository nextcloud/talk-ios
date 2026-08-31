//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

extension UIScrollView {

    /// Fades out a horizontal edge that can be scrolled towards, so it is visible that there is more content.
    /// Call this from `layoutSubviews`, which is also run while scrolling.
    func updateHorizontalScrollFade(fadeWidth: CGFloat = 16) {
        guard self.bounds.width > 0 else { return }

        let minOffset = -self.adjustedContentInset.left
        let maxOffset = self.contentSize.width + self.adjustedContentInset.right - self.bounds.width

        let canScrollToLeading = self.contentOffset.x > minOffset + 1
        let canScrollToTrailing = self.contentOffset.x < maxOffset - 1

        guard canScrollToLeading || canScrollToTrailing else {
            self.layer.mask = nil
            return
        }

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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeLayer.frame = self.bounds
        fadeLayer.colors = [canScrollToLeading ? clear : opaque, opaque, opaque, canScrollToTrailing ? clear : opaque]
        fadeLayer.locations = [0, NSNumber(value: fade), NSNumber(value: 1 - fade), 1]
        CATransaction.commit()
    }
}

/// Scroll view that fades out a horizontal edge that can be scrolled towards
class FadingScrollView: UIScrollView {

    override func layoutSubviews() {
        super.layoutSubviews()
        self.updateHorizontalScrollFade()
    }
}
