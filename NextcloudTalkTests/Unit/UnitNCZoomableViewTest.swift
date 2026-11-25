//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitNCZoomableViewTest: XCTestCase {

    // A view showing a 4:3 image in a portrait viewport, fitted to 300x225
    private func makeZoomableView() -> NCZoomableView {
        let zoomableView = NCZoomableView(frame: .init(x: 0, y: 0, width: 300, height: 600))
        zoomableView.setContent(UIView(), size: .init(width: 4000, height: 3000))

        return zoomableView
    }

    // The scroll view pins small content to the top left, we center it instead
    func testUnzoomedContentIsCentered() {
        let zoomableView = self.makeZoomableView()
        let contentFrame = zoomableView.contentView.convert(zoomableView.contentView.bounds, to: zoomableView)

        XCTAssertEqual(contentFrame.width, 300, accuracy: 0.01)
        XCTAssertEqual(contentFrame.height, 225, accuracy: 0.01)
        // The scroll view rounds its offset to device pixels
        XCTAssertEqual(contentFrame.midX, 150, accuracy: 0.5)
        XCTAssertEqual(contentFrame.midY, 300, accuracy: 0.5)
    }

    func testZoomingToANormalizedRectShowsThatRegion() {
        let zoomableView = self.makeZoomableView()

        // The top left quarter is 150 wide, so it fills the 300 wide viewport at 2x
        zoomableView.zoom(toNormalizedRect: .init(x: 0, y: 0, width: 0.5, height: 0.5))

        let restored = zoomableView.normalizedVisibleRect

        XCTAssertEqual(zoomableView.scrollView.zoomScale, 2, accuracy: 0.01)
        XCTAssertEqual(restored.minX, 0, accuracy: 0.01)
        XCTAssertEqual(restored.width, 0.5, accuracy: 0.01)
    }

    // Swapping the preview for the original triggers a layout pass, which must not reset the zoom
    func testLayoutPassWithoutSizeChangeKeepsTheZoom() {
        let zoomableView = self.makeZoomableView()

        zoomableView.zoom(toNormalizedRect: .init(x: 0.1, y: 0.2, width: 0.3, height: 0.3))

        let zoomScaleBefore = zoomableView.scrollView.zoomScale
        let offsetBefore = zoomableView.scrollView.contentOffset

        zoomableView.setNeedsLayout()
        zoomableView.layoutIfNeeded()

        XCTAssertTrue(zoomableView.isZoomed)
        XCTAssertEqual(zoomableView.scrollView.zoomScale, zoomScaleBefore)
        XCTAssertEqual(zoomableView.scrollView.contentOffset, offsetBefore)
    }

    // Swapping the preview for the original of the same shape must not move anything
    func testSameAspectContentSizeKeepsTheZoom() {
        let zoomableView = self.makeZoomableView()

        zoomableView.zoom(toNormalizedRect: .init(x: 0.1, y: 0.2, width: 0.3, height: 0.3))

        let zoomScaleBefore = zoomableView.scrollView.zoomScale
        let offsetBefore = zoomableView.scrollView.contentOffset

        zoomableView.contentViewSize = .init(width: 8000, height: 6000)

        XCTAssertEqual(zoomableView.scrollView.zoomScale, zoomScaleBefore)
        XCTAssertEqual(zoomableView.scrollView.contentOffset, offsetBefore)
    }

    // A preview with a different shape than the original keeps the region the user zoomed into
    func testDifferentAspectContentSizeKeepsTheVisibleRegion() {
        let zoomableView = self.makeZoomableView()

        zoomableView.zoom(toNormalizedRect: .init(x: 0.2, y: 0.2, width: 0.3, height: 0.3))
        let region = zoomableView.normalizedVisibleRect

        zoomableView.contentViewSize = .init(width: 3000, height: 4000)

        let restored = zoomableView.normalizedVisibleRect

        XCTAssertTrue(zoomableView.isZoomed)
        XCTAssertLessThanOrEqual(restored.minX, region.minX + 0.01)
        XCTAssertLessThanOrEqual(restored.minY, region.minY + 0.01)
        XCTAssertGreaterThanOrEqual(restored.maxX, region.maxX - 0.01)
        XCTAssertGreaterThanOrEqual(restored.maxY, region.maxY - 0.01)
    }

    // Rotation keeps the zoom and the content point at the center
    func testSizeChangeKeepsZoomAndCenter() {
        let zoomableView = self.makeZoomableView()

        zoomableView.zoom(toNormalizedRect: .init(x: 0.3, y: 0.4, width: 0.2, height: 0.2))
        let zoomScale = zoomableView.scrollView.zoomScale
        let before = zoomableView.normalizedVisibleRect

        zoomableView.frame = .init(x: 0, y: 0, width: 600, height: 300)
        zoomableView.layoutIfNeeded()

        let rotated = zoomableView.normalizedVisibleRect

        XCTAssertEqual(zoomableView.scrollView.zoomScale, zoomScale, accuracy: 0.01)
        XCTAssertEqual(rotated.midX, before.midX, accuracy: 0.01)
        XCTAssertEqual(rotated.midY, before.midY, accuracy: 0.01)
    }

    // A refit unzooms internally, which must not reach the media viewer as two zoom changes
    func testSizeChangeWhileZoomedDoesNotReportAZoomChange() {
        let zoomableView = self.makeZoomableView()
        var reports = 0
        zoomableView.onZoomChange = { reports += 1 }

        zoomableView.zoom(toNormalizedRect: .init(x: 0.3, y: 0.4, width: 0.2, height: 0.2))
        XCTAssertEqual(reports, 1)

        zoomableView.frame = .init(x: 0, y: 0, width: 600, height: 300)
        zoomableView.layoutIfNeeded()
        zoomableView.contentViewSize = .init(width: 3000, height: 4000)

        XCTAssertEqual(reports, 1)
        XCTAssertTrue(zoomableView.isZoomed)
    }

    // The callers rely on the view refitting itself on size changes
    func testSizeChangeWhileNotZoomedRefits() {
        let zoomableView = self.makeZoomableView()

        zoomableView.frame = .init(x: 0, y: 0, width: 600, height: 300)
        zoomableView.layoutIfNeeded()

        // 4:3 fitted into 600x300 is 400x300
        XCTAssertFalse(zoomableView.isZoomed)
        XCTAssertEqual(zoomableView.contentView.frame.size.width, 400, accuracy: 0.01)
        XCTAssertEqual(zoomableView.contentView.frame.size.height, 300, accuracy: 0.01)
    }
}
