//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitNCZoomableViewTest: XCTestCase {

    // A view showing a 4:3 image in a portrait viewport, laid out and ready to zoom
    private func makeZoomableView(contentSize: CGSize = .init(width: 4000, height: 3000)) -> NCZoomableView {
        let zoomableView = NCZoomableView(frame: .init(x: 0, y: 0, width: 300, height: 600))
        zoomableView.contentViewSize = contentSize
        zoomableView.layoutIfNeeded()
        zoomableView.resizeContentView()

        return zoomableView
    }

    func testUnzoomedVisibleRectCoversTheWholeContent() {
        let zoomableView = self.makeZoomableView()
        let visibleRect = zoomableView.normalizedVisibleRect

        // The content is fitted, so it is fully visible horizontally
        XCTAssertEqual(visibleRect.minX, 0, accuracy: 0.01)
        XCTAssertEqual(visibleRect.width, 1, accuracy: 0.01)
        XCTAssertFalse(zoomableView.isZoomed)
    }

    func testRestoringAVisibleRectShowsThatRegion() {
        let zoomableView = self.makeZoomableView()

        // Top left quarter of the content
        let region = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        zoomableView.restoreVisibleRect(region)

        let restored = zoomableView.normalizedVisibleRect

        // At least the requested region has to be visible
        XCTAssertLessThanOrEqual(restored.minX, region.minX + 0.01)
        XCTAssertLessThanOrEqual(restored.minY, region.minY + 0.01)
        XCTAssertGreaterThanOrEqual(restored.maxX, region.maxX - 0.01)
        XCTAssertGreaterThanOrEqual(restored.maxY, region.maxY - 0.01)
    }

    func testRestoringIsStableAcrossARepeatedRoundTrip() {
        let zoomableView = self.makeZoomableView()

        zoomableView.restoreVisibleRect(.init(x: 0.25, y: 0.3, width: 0.4, height: 0.4))
        let firstRect = zoomableView.normalizedVisibleRect

        zoomableView.restoreVisibleRect(firstRect)
        let secondRect = zoomableView.normalizedVisibleRect

        XCTAssertEqual(firstRect.minX, secondRect.minX, accuracy: 0.01)
        XCTAssertEqual(firstRect.minY, secondRect.minY, accuracy: 0.01)
        XCTAssertEqual(firstRect.width, secondRect.width, accuracy: 0.01)
        XCTAssertEqual(firstRect.height, secondRect.height, accuracy: 0.01)
    }

    // Replacing a preview with the original of the same shape must not move anything
    func testReplacingContentWithTheSameAspectRatioKeepsTheZoom() {
        let zoomableView = self.makeZoomableView(contentSize: .init(width: 480, height: 360))

        zoomableView.restoreVisibleRect(.init(x: 0.1, y: 0.2, width: 0.3, height: 0.3))

        let transformBefore = zoomableView.contentView.transform
        let frameBefore = zoomableView.contentView.frame

        // Same aspect ratio, so the media viewer does not touch the geometry at all
        zoomableView.contentViewSize = .init(width: 4000, height: 3000)

        XCTAssertEqual(zoomableView.contentView.transform, transformBefore)
        XCTAssertEqual(zoomableView.contentView.frame, frameBefore)
    }

    // The same region has to stay visible when the content changes shape
    func testRestoringAcrossADifferentAspectRatioKeepsTheRegionVisible() {
        let zoomableView = self.makeZoomableView(contentSize: .init(width: 4000, height: 3000))

        zoomableView.restoreVisibleRect(.init(x: 0.2, y: 0.2, width: 0.3, height: 0.3))
        let region = zoomableView.normalizedVisibleRect

        zoomableView.contentViewSize = .init(width: 3000, height: 4000)
        zoomableView.restoreVisibleRect(region)

        let restored = zoomableView.normalizedVisibleRect

        XCTAssertLessThanOrEqual(restored.minX, region.minX + 0.01)
        XCTAssertLessThanOrEqual(restored.minY, region.minY + 0.01)
        XCTAssertGreaterThanOrEqual(restored.maxX, region.maxX - 0.01)
        XCTAssertGreaterThanOrEqual(restored.maxY, region.maxY - 0.01)
    }

    // Zoom is not capped, a small region is restored at whatever zoom it takes
    func testRestoringASmallRegionIsNotCapped() {
        let zoomableView = self.makeZoomableView()

        // The content is fitted to 300x225, so 1% of it needs a 100x zoom to fill the width
        zoomableView.restoreVisibleRect(.init(x: 0.5, y: 0.5, width: 0.01, height: 0.01))

        XCTAssertEqual(zoomableView.contentView.transform.a, 100, accuracy: 0.5)
    }

    func testRestoringNeverZoomsBelowTheFittedSize() {
        let zoomableView = self.makeZoomableView()

        // A region larger than the content would mean zooming out
        zoomableView.restoreVisibleRect(.init(x: -0.5, y: -0.5, width: 2, height: 2))

        XCTAssertEqual(zoomableView.contentView.transform.a, 1, accuracy: 0.01)
    }

    func testResizingReturnsToTheFittedSize() {
        let zoomableView = self.makeZoomableView()

        zoomableView.restoreVisibleRect(.init(x: 0.1, y: 0.1, width: 0.3, height: 0.3))
        XCTAssertTrue(zoomableView.isZoomed)

        zoomableView.resizeContentView()
        XCTAssertFalse(zoomableView.isZoomed)
    }
}
