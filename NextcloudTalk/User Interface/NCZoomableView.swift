//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objc protocol NCZoomableViewDelegate {
    @objc func contentViewZoomDidChange(_ view: NCZoomableView, _ scale: Double)
}

@objcMembers class NCZoomableView: UIView, UIGestureRecognizerDelegate {

    public weak var delegate: NCZoomableViewDelegate?

    public var disablePanningOnInitialZoom = false

    var pinchGestureRecognizer: UIPinchGestureRecognizer?
    var panGestureRecognizer: UIPanGestureRecognizer?
    var doubleTapGestureRecoginzer: UITapGestureRecognizer?

    private(set) var contentView = UIView()
    var contentViewSize = CGSize()

    public var isZoomed: Bool {
        let scaleFactor = self.contentView.transform.a
        return scaleFactor != 1
    }

    // The visible part of the content, in normalized content coordinates
    public var normalizedVisibleRect: CGRect {
        let contentBounds = self.contentView.bounds

        guard contentBounds.width > 0, contentBounds.height > 0 else { return .init(x: 0, y: 0, width: 1, height: 1) }

        let visibleRect = self.convert(self.bounds, to: self.contentView)

        return CGRect(x: visibleRect.minX / contentBounds.width,
                      y: visibleRect.minY / contentBounds.height,
                      width: visibleRect.width / contentBounds.width,
                      height: visibleRect.height / contentBounds.height)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.addSubview(self.contentView)
        self.initGestureRecognizers()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        self.addSubview(self.contentView)
        self.initGestureRecognizers()
    }

    func initGestureRecognizers() {
        self.pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        self.pinchGestureRecognizer?.delegate = self
        self.addGestureRecognizer(self.pinchGestureRecognizer!)

        self.panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        self.panGestureRecognizer?.delegate = self
        self.addGestureRecognizer(self.panGestureRecognizer!)

        self.doubleTapGestureRecoginzer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        self.doubleTapGestureRecoginzer?.delegate = self
        self.doubleTapGestureRecoginzer?.numberOfTapsRequired = 2
        self.contentView.addGestureRecognizer(self.doubleTapGestureRecoginzer!)
    }

    public func replaceContentView(_ newView: UIView) {
        if let pinchGestureRecognizer = self.pinchGestureRecognizer {
            self.removeGestureRecognizer(pinchGestureRecognizer)
        }

        if let panGestureRecognizer = self.panGestureRecognizer {
            self.removeGestureRecognizer(panGestureRecognizer)
        }

        if let doubleTapGestureRecoginzer = self.doubleTapGestureRecoginzer {
            self.contentView.removeGestureRecognizer(doubleTapGestureRecoginzer)
        }

        self.contentView.removeFromSuperview()
        self.contentView = newView
        self.contentViewSize = newView.frame.size
        self.addSubview(self.contentView)

        self.initGestureRecognizers()
        self.resizeContentView()
    }

    func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        self.zoomView(view: self.contentView, toPoint: recognizer.location(in: self.contentView), usingScale: recognizer.scale)
        recognizer.scale = 1

        if recognizer.state == .ended {
            let bounds = self.contentView.bounds
            let zoomedSize = self.contentView.frame.size

            let aspectRatioContentViewSize = AVMakeRect(aspectRatio: self.contentViewSize, insideRect: bounds).size

            // Don't zoom smaller than the original size
            if zoomedSize.width < aspectRatioContentViewSize.width || zoomedSize.height < aspectRatioContentViewSize.height {
                UIView.animate(withDuration: 0.3) {
                    self.resizeContentView()
                }
            } else {
                self.adjustViewPosition()
            }

        }
    }

    func handlePan(_ recognizer: UIPanGestureRecognizer) {
        if self.disablePanningOnInitialZoom, !self.isZoomed {
            return
        }

        let point = recognizer.translation(in: self.contentView)

        // We need to take the current scaling into account when panning
        // As we have the same scale factor for X and Y, we can take only one here
        let scaleFactor = self.contentView.transform.a

        self.contentView.center = CGPoint(x: self.contentView.center.x + point.x * scaleFactor, y: self.contentView.center.y + point.y * scaleFactor)
        recognizer.setTranslation(.zero, in: self.contentView)

        if recognizer.state == .ended {
            self.adjustViewPosition()
        }
    }

    func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if recognizer.state == .recognized {
            // We need to take the current scaling into account when panning
            // As we have the same scale factor for X and Y, we can take only one here
            let scaleFactor = self.contentView.transform.a

            UIView.animate(withDuration: 0.3) {
                if scaleFactor > 1 {
                    // Set screenView's original size
                    self.resizeContentView()
                } else {
                    // Zoom 3x screenView into the tap point
                    self.zoomView(view: recognizer.view!, toPoint: recognizer.location(in: recognizer.view!), usingScale: 3)
                }
            }

            self.adjustViewPosition()
        }
    }

    func zoomView(view: UIView, toPoint point: CGPoint, usingScale scale: CGFloat) {
        let bounds = view.bounds

        var resultPoint = point
        resultPoint.x -= bounds.midX
        resultPoint.y -= bounds.midY

        var transform = view.transform
        transform = CGAffineTransformTranslate(transform, resultPoint.x, resultPoint.y)
        transform = CGAffineTransformScale(transform, scale, scale)
        transform = CGAffineTransformTranslate(transform, -resultPoint.x, -resultPoint.y)
        view.transform = transform

        self.delegate?.contentViewZoomDidChange(self, transform.a)
    }

    func adjustViewPosition() {
        let frame = self.adjustedContentViewFrame()

        UIView.animate(withDuration: 0.3) {
            self.contentView.frame = frame
        }
    }

    // Keeps the content from being panned away from the viewport
    private func adjustedContentViewFrame() -> CGRect {
        let parentSize = self.frame.size
        let size = self.contentView.frame.size
        var position = self.contentView.frame.origin

        let viewLeft = position.x
        let viewRight = position.x + size.width
        let viewTop = position.y
        let viewBottom = position.y + size.height

        // Left align screenView if it has been moved to the center (and it is wide enough)
        if viewLeft > 0, size.width >= parentSize.width {
            position = CGPoint(x: 0, y: position.y)
        }

        // Top align screenView if it has been moved to the center (and it is tall enough)
        if viewTop > 0, size.height >= parentSize.height {
            position = CGPoint(x: position.x, y: 0)
        }

        // Right align screenView if it has been moved to the center (and it is wide enough)
        if viewRight < parentSize.width, size.width >= parentSize.width {
            position = CGPoint(x: parentSize.width - size.width, y: position.y)
        }

        // Bottom align screenView if it has been moved to the center (and it is tall enough)
        if viewBottom < parentSize.height, size.height >= parentSize.height {
            position = CGPoint(x: position.x, y: parentSize.height - size.height)
        }

        // Align screenView vertically
        if size.width <= parentSize.width {
            position = CGPoint(x: parentSize.width / 2 - size.width / 2, y: position.y)
        }

        // Align screenView horizontally
        if size.height <= parentSize.height {
            position = CGPoint(x: position.x, y: parentSize.height / 2 - size.height / 2)
        }

        var frame = self.contentView.frame
        frame.origin.x = position.x
        frame.origin.y = position.y

        return frame
    }

    public func resizeContentView() {
        self.contentView.transform = .identity
        self.delegate?.contentViewZoomDidChange(self, self.contentView.transform.a)

        let bounds = self.bounds
        let contentSize = self.contentViewSize

        if contentSize.width > 0, contentSize.height > 0 {
            let aspectFrame = AVMakeRect(aspectRatio: contentSize, insideRect: bounds)
            self.contentView.frame = aspectFrame
            self.contentView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        } else {
            self.contentView.frame = bounds
        }
    }

    ///
    /// Zooms and positions the content so that `normalizedRect` is visible again.
    ///
    /// Used when the content is replaced while the user is zoomed in. The region is fitted into the
    /// viewport, so the user always sees at least what was visible before.
    ///
    public func restoreVisibleRect(_ normalizedRect: CGRect) {
        self.resizeContentView()

        let contentBounds = self.contentView.bounds

        guard contentBounds.width > 0, contentBounds.height > 0,
              normalizedRect.width > 0, normalizedRect.height > 0,
              self.bounds.width > 0, self.bounds.height > 0
        else { return }

        let region = CGRect(x: normalizedRect.minX * contentBounds.width,
                            y: normalizedRect.minY * contentBounds.height,
                            width: normalizedRect.width * contentBounds.width,
                            height: normalizedRect.height * contentBounds.height)

        // Never below the fitted size, that is what resizeContentView() is for
        let scale = max(min(self.bounds.width / region.width, self.bounds.height / region.height), 1)

        self.contentView.transform = CGAffineTransform(scaleX: scale, y: scale)

        // Move the region's center onto our center
        let regionCenter = self.contentView.convert(CGPoint(x: region.midX, y: region.midY), to: self)
        self.contentView.center = CGPoint(x: self.contentView.center.x + self.bounds.midX - regionCenter.x,
                                          y: self.contentView.center.y + self.bounds.midY - regionCenter.y)

        self.contentView.frame = self.adjustedContentViewFrame()

        self.delegate?.contentViewZoomDidChange(self, scale)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
