//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation
import UIKit

// A UIView wrapping the scroll view, so overlays added as our subviews do not scroll with the content
class NCZoomableView: UIView, UIScrollViewDelegate {

    var onZoomChange: (() -> Void)?

    // Panning the unzoomed content hints that zooming is possible, but it steals swipes from an enclosing page view controller
    var bouncesWhenNotZoomed = true {
        didSet {
            self.scrollView.alwaysBounceHorizontal = self.bouncesWhenNotZoomed
            self.scrollView.alwaysBounceVertical = self.bouncesWhenNotZoomed
        }
    }

    // Only the aspect ratio is used, zero fills the viewport
    var contentViewSize: CGSize {
        get { self.mediaSize }
        set {
            let needsRefit = !Self.aspectMatches(self.mediaSize, newValue)
            let visibleRect = self.isZoomed ? self.normalizedVisibleRect : nil

            self.mediaSize = newValue

            guard needsRefit else { return }

            self.withoutZoomReports {
                self.resetZoom()

                if let visibleRect {
                    self.zoom(toNormalizedRect: visibleRect)
                }
            }
        }
    }

    var isZoomed: Bool {
        // Below the minimum is only the bounce of a pinch
        return self.scrollView.zoomScale > self.scrollView.minimumZoomScale + 0.001
    }

    let scrollView = UIScrollView()
    let doubleTapGestureRecognizer = UITapGestureRecognizer()
    private(set) var contentView = UIView()

    private var mediaSize = CGSize.zero
    private var reportedIsZoomed = false
    private var isRefitting = false

    // The viewport size the content was last fitted to, and the normalized content point shown at its center
    private var fittedViewportSize = CGSize.zero
    private var normalizedCenter = CGPoint(x: 0.5, y: 0.5)

    // The visible part of the content, in normalized content coordinates
    var normalizedVisibleRect: CGRect {
        let contentBounds = self.contentView.bounds

        guard contentBounds.width > 0, contentBounds.height > 0 else { return .init(x: 0, y: 0, width: 1, height: 1) }

        let visibleRect = self.scrollView.convert(self.scrollView.bounds, to: self.contentView)

        return CGRect(x: visibleRect.minX / contentBounds.width,
                      y: visibleRect.minY / contentBounds.height,
                      width: visibleRect.width / contentBounds.width,
                      height: visibleRect.height / contentBounds.height)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.commonInit()
    }

    private func commonInit() {
        self.scrollView.frame = self.bounds
        self.scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.scrollView.delegate = self
        self.scrollView.maximumZoomScale = 10
        self.scrollView.showsHorizontalScrollIndicator = false
        self.scrollView.showsVerticalScrollIndicator = false
        // Safe area insets would add to the insets that center the content
        self.scrollView.contentInsetAdjustmentBehavior = .never
        self.scrollView.alwaysBounceHorizontal = true
        self.scrollView.alwaysBounceVertical = true

        // Below any overlays the xib or the owner adds
        self.insertSubview(self.scrollView, at: 0)
        self.scrollView.addSubview(self.contentView)

        self.doubleTapGestureRecognizer.addTarget(self, action: #selector(handleDoubleTap(_:)))
        self.doubleTapGestureRecognizer.numberOfTapsRequired = 2
        self.scrollView.addGestureRecognizer(self.doubleTapGestureRecognizer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard self.scrollView.bounds.size != self.fittedViewportSize else { return }

        // Keep zoom and center across rotation and other size changes
        let zoomScale = self.scrollView.zoomScale
        let center = self.normalizedCenter

        self.withoutZoomReports {
            self.resetZoom()

            if zoomScale > self.scrollView.minimumZoomScale {
                self.zoom(toNormalizedCenter: center, scale: zoomScale)
            }
        }
    }

    // MARK: - Content

    func setContent(_ view: UIView, size: CGSize) {
        // Unzoom first so the removed view is not left scaled, the call screen reads its frame as the remembered size
        self.scrollView.zoomScale = self.scrollView.minimumZoomScale
        self.contentView.removeFromSuperview()

        self.contentView = view
        self.mediaSize = size
        self.scrollView.addSubview(view)

        self.resetZoom()
    }

    // Fits the content into the viewport, unzoomed and centered
    func resetZoom() {
        self.scrollView.zoomScale = self.scrollView.minimumZoomScale
        self.contentView.transform = .identity

        let bounds = self.scrollView.bounds
        var fittedSize = bounds.size

        if self.mediaSize.width > 0, self.mediaSize.height > 0 {
            fittedSize = AVMakeRect(aspectRatio: self.mediaSize, insideRect: bounds).size
        }

        self.fittedViewportSize = bounds.size
        self.contentView.frame = CGRect(origin: .zero, size: fittedSize)
        self.scrollView.contentSize = fittedSize
        self.centerContent()
        self.scrollView.contentOffset = CGPoint(x: -self.scrollView.contentInset.left, y: -self.scrollView.contentInset.top)
        self.normalizedCenter = CGPoint(x: 0.5, y: 0.5)

        self.reportZoomChangeIfNeeded()
    }

    // MARK: - Zooming

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if self.isZoomed {
            self.scrollView.setZoomScale(self.scrollView.minimumZoomScale, animated: true)
            return
        }

        let point = recognizer.location(in: self.contentView)
        guard self.contentView.bounds.contains(point) else { return }

        let scale = min(3, self.scrollView.maximumZoomScale)
        let size = CGSize(width: self.scrollView.bounds.width / scale, height: self.scrollView.bounds.height / scale)
        let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)

        self.scrollView.zoom(to: rect, animated: true)
    }

    // Fits the normalized region into the viewport, so at least that region is visible, up to the maximum zoom
    func zoom(toNormalizedRect normalizedRect: CGRect) {
        let contentBounds = self.contentView.bounds
        let viewport = self.scrollView.bounds.size

        guard contentBounds.width > 0, contentBounds.height > 0,
              normalizedRect.width > 0, normalizedRect.height > 0,
              viewport.width > 0, viewport.height > 0
        else { return }

        let fittingScale = min(viewport.width / (normalizedRect.width * contentBounds.width),
                               viewport.height / (normalizedRect.height * contentBounds.height))

        self.zoom(toNormalizedCenter: CGPoint(x: normalizedRect.midX, y: normalizedRect.midY), scale: fittingScale)
    }

    // Moves the normalized content point onto the viewport's center, without leaving the content
    private func zoom(toNormalizedCenter center: CGPoint, scale: CGFloat) {
        self.scrollView.zoomScale = min(max(scale, self.scrollView.minimumZoomScale), self.scrollView.maximumZoomScale)
        self.centerContent()

        let contentBounds = self.contentView.bounds
        let viewport = self.scrollView.bounds.size
        let zoomScale = self.scrollView.zoomScale
        let insets = self.scrollView.contentInset
        let zoomedSize = self.scrollView.contentSize

        let offsetX = center.x * contentBounds.width * zoomScale - viewport.width / 2
        let offsetY = center.y * contentBounds.height * zoomScale - viewport.height / 2

        let maxOffsetX = max(zoomedSize.width + insets.right - viewport.width, -insets.left)
        let maxOffsetY = max(zoomedSize.height + insets.bottom - viewport.height, -insets.top)

        self.scrollView.contentOffset = CGPoint(x: min(max(offsetX, -insets.left), maxOffsetX),
                                                y: min(max(offsetY, -insets.top), maxOffsetY))

        // An unchanged offset sends no scrollViewDidScroll
        self.recordNormalizedCenter()
    }

    // MARK: - Helpers

    // Content smaller than the viewport is centered instead of pinned to the top left
    private func centerContent() {
        let boundsSize = self.scrollView.bounds.size
        let contentSize = self.scrollView.contentSize

        let horizontal = max((boundsSize.width - contentSize.width) / 2, 0)
        let vertical = max((boundsSize.height - contentSize.height) / 2, 0)

        let insets = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)

        if self.scrollView.contentInset != insets {
            self.scrollView.contentInset = insets
        }
    }

    // Only while the viewport is the one we fitted to, a size change in flight must not overwrite the center we restore
    private func recordNormalizedCenter() {
        guard self.scrollView.bounds.size == self.fittedViewportSize else { return }

        let visibleRect = self.normalizedVisibleRect
        self.normalizedCenter = CGPoint(x: visibleRect.midX, y: visibleRect.midY)
    }

    // A refit unzooms before zooming again, which must not look like two zoom changes
    private func withoutZoomReports(_ body: () -> Void) {
        self.isRefitting = true
        body()
        self.isRefitting = false

        self.reportZoomChangeIfNeeded()
    }

    private func reportZoomChangeIfNeeded() {
        guard !self.isRefitting, self.isZoomed != self.reportedIsZoomed else { return }

        self.reportedIsZoomed = self.isZoomed
        self.onZoomChange?()
    }

    private static func aspectMatches(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        guard lhs.width > 0, lhs.height > 0, rhs.width > 0, rhs.height > 0 else { return lhs == rhs }

        return abs((lhs.width / lhs.height) - (rhs.width / rhs.height)) < 0.01
    }

    // MARK: - UIScrollView delegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return self.contentView
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        self.recordNormalizedCenter()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        self.centerContent()
        self.recordNormalizedCenter()
        self.reportZoomChangeIfNeeded()
    }
}
