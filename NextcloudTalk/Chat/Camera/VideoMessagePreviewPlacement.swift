//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

/// Where the live preview of a video message recording is shown in the chat. This is pure arithmetic, so it can be
/// tested without a screen.
enum VideoMessagePreviewPlacement {

    /// The gap kept free at every edge of the area
    static let margin: CGFloat = 16

    /// The part of the width of the area the preview takes at most
    static let maxWidthFraction: CGFloat = 0.75

    /// The longest side the preview has at most, so it does not grow without limit on an iPad
    static let maxSide: CGFloat = 480

    static let portraitAspect: CGFloat = 9.0 / 16.0
    static let landscapeAspect: CGFloat = 16.0 / 9.0

    /// A margin may not eat the area: at most this part of the shorter side is kept free at every edge
    private static let marginDivisor: CGFloat = 8

    /// Width divided by height of the frame the viewer sees in the given orientation of the interface:
    /// 9:16 in portrait, 16:9 in landscape. The orientation of the file that is recorded does not matter here.
    static func frameAspect(for orientation: UIInterfaceOrientation) -> CGFloat {
        return orientation.isLandscape ? self.landscapeAspect : self.portraitAspect
    }

    /// Fits a frame of the given aspect ratio into the area and centers it there. A portrait frame is limited by the
    /// width of the area and by its height, a landscape frame is fitted by the height when the area is low: the frame
    /// is never distorted, only scaled down. An area without size gives an empty rect.
    ///
    /// - Parameters:
    ///   - area: the free space, between the top of the safe area and the top of the recording panel
    ///   - aspect: width divided by height of the frame, a value that is not usable is read as portrait
    ///   - margin: the gap kept free at every edge of the area, shrinks on a very small area
    ///   - maxWidthFraction: the part of the width of the area the preview takes at most
    ///   - maxSide: the longest side the preview has at most
    static func frame(in area: CGRect,
                      aspect: CGFloat,
                      margin: CGFloat = VideoMessagePreviewPlacement.margin,
                      maxWidthFraction: CGFloat = VideoMessagePreviewPlacement.maxWidthFraction,
                      maxSide: CGFloat = VideoMessagePreviewPlacement.maxSide) -> CGRect {
        // Not `area.width`, which is the absolute value for a rect with a negative size
        let areaWidth = max(area.size.width, 0)
        let areaHeight = max(area.size.height, 0)
        let origin = area.origin

        guard areaWidth.isFinite, areaHeight.isFinite, areaWidth > 0, areaHeight > 0 else {
            return CGRect(origin: origin, size: .zero)
        }

        let safeAspect = (aspect.isFinite && aspect > 0) ? aspect : self.portraitAspect
        let safeMargin = max(min(margin, min(areaWidth, areaHeight) / self.marginDivisor), 0)

        let boxWidth = max(min(areaWidth - 2 * safeMargin, areaWidth * maxWidthFraction), 0)
        let boxHeight = max(areaHeight - 2 * safeMargin, 0)

        var width = boxWidth
        var height = width / safeAspect

        if height > boxHeight {
            height = boxHeight
            width = height * safeAspect
        }

        let longest = max(width, height)

        if longest > maxSide, longest > 0 {
            let scale = maxSide / longest
            width *= scale
            height *= scale
        }

        width = width.rounded()
        height = height.rounded()

        return CGRect(x: origin.x + ((areaWidth - width) / 2).rounded(),
                      y: origin.y + ((areaHeight - height) / 2).rounded(),
                      width: width,
                      height: height)
    }
}
