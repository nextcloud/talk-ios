//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import XCTest
@testable import NextcloudTalk

final class UnitVideoMessagePreviewPlacementTest: XCTestCase {

    private let portrait = VideoMessagePreviewPlacement.portraitAspect
    private let landscape = VideoMessagePreviewPlacement.landscapeAspect

    private func place(_ width: CGFloat, _ height: CGFloat, aspect: CGFloat, origin: CGPoint = .zero) -> CGRect {
        return VideoMessagePreviewPlacement.frame(in: CGRect(origin: origin, size: CGSize(width: width, height: height)), aspect: aspect)
    }

    private func assertInside(_ rect: CGRect, _ area: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(rect.minX, area.minX, file: file, line: line)
        XCTAssertGreaterThanOrEqual(rect.minY, area.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(rect.maxX, area.maxX, file: file, line: line)
        XCTAssertLessThanOrEqual(rect.maxY, area.maxY, file: file, line: line)
    }

    private func assertAspect(_ rect: CGRect, _ aspect: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rect.width / rect.height, aspect, accuracy: 0.03, file: file, line: line)
    }

    // MARK: - Size

    func testPortraitTakesThreeQuartersOfTheWidthAndKeepsTheAspect() throws {
        let rect = self.place(348, 560, aspect: self.portrait)

        XCTAssertEqual(rect.width, 261)
        XCTAssertEqual(rect.height, 464)
        self.assertAspect(rect, self.portrait)
        self.assertInside(rect, CGRect(x: 0, y: 0, width: 348, height: 560))
    }

    func testPreviewIsCenteredInTheAreaAndFollowsItsOrigin() throws {
        let area = CGRect(x: 10, y: 100, width: 348, height: 560)
        let rect = VideoMessagePreviewPlacement.frame(in: area, aspect: self.portrait)

        XCTAssertEqual(rect.midX, area.midX, accuracy: 1)
        XCTAssertEqual(rect.midY, area.midY, accuracy: 1)
    }

    func testPortraitInALowAreaIsFittedByTheHeightWithMargins() throws {
        let rect = self.place(348, 400, aspect: self.portrait)

        // 400 - 2 * 16
        XCTAssertEqual(rect.height, 368)
        XCTAssertEqual(rect.width, 207)
        self.assertAspect(rect, self.portrait)
    }

    func testLandscapeOnAPhoneInLandscapeIsFittedByTheHeightAndNotSquashed() throws {
        // Landscape iPhone: the area between the navigation bar and the recording panel is low
        let area = CGRect(x: 0, y: 50, width: 700, height: 200)
        let rect = VideoMessagePreviewPlacement.frame(in: area, aspect: self.landscape)

        XCTAssertEqual(rect.height, 168)
        XCTAssertEqual(rect.width, 299)
        self.assertAspect(rect, self.landscape)
        self.assertInside(rect, area.insetBy(dx: 16, dy: 16))
    }

    func testLandscapeInAPortraitAreaIsFittedByTheWidth() throws {
        let rect = self.place(348, 560, aspect: self.landscape)

        XCTAssertEqual(rect.width, 261)
        XCTAssertEqual(rect.height, 147)
        self.assertAspect(rect, self.landscape)
    }

    func testNarrowAreaKeepsTheAspectAndTheMargin() throws {
        let rect = self.place(240, 520, aspect: self.portrait)

        // 75 % of 240, the margins would allow 208
        XCTAssertEqual(rect.width, 180)
        XCTAssertEqual(rect.height, 320)
        self.assertAspect(rect, self.portrait)
    }

    func testMarginLimitsTheWidthWhenItIsNarrowerThanTheFraction() throws {
        let rect = VideoMessagePreviewPlacement.frame(in: CGRect(x: 0, y: 0, width: 200, height: 520), aspect: self.landscape, maxWidthFraction: 0.95)

        // 200 - 2 * 16 is less than 95 % of 200
        XCTAssertEqual(rect.width, 168)
        self.assertAspect(rect, self.landscape)
    }

    func testVeryLowAreaStillGivesAPreviewInsideTheArea() throws {
        let area = CGRect(x: 0, y: 0, width: 348, height: 40)
        let rect = VideoMessagePreviewPlacement.frame(in: area, aspect: self.portrait)

        XCTAssertGreaterThan(rect.height, 0)
        XCTAssertGreaterThan(rect.width, 0)
        self.assertAspect(rect, self.portrait)
        self.assertInside(rect, area)

        let landscapeArea = CGRect(x: 0, y: 0, width: 700, height: 24)
        let landscapeRect = VideoMessagePreviewPlacement.frame(in: landscapeArea, aspect: self.landscape)

        XCTAssertGreaterThan(landscapeRect.height, 0)
        self.assertAspect(landscapeRect, self.landscape)
        self.assertInside(landscapeRect, landscapeArea)
    }

    func testIPadIsCappedByTheLongestSide() throws {
        let portraitRect = self.place(1000, 1000, aspect: self.portrait)

        XCTAssertEqual(portraitRect.height, 480)
        XCTAssertEqual(portraitRect.width, 270)
        self.assertAspect(portraitRect, self.portrait)

        let landscapeRect = self.place(1100, 700, aspect: self.landscape)

        XCTAssertEqual(landscapeRect.width, 480)
        XCTAssertEqual(landscapeRect.height, 270)
        self.assertAspect(landscapeRect, self.landscape)
    }

    // MARK: - Areas without size

    func testEmptyAreaGivesAnEmptyRect() throws {
        XCTAssertEqual(self.place(0, 0, aspect: self.portrait).size, .zero)
        XCTAssertEqual(self.place(348, 0, aspect: self.portrait).size, .zero)
        XCTAssertEqual(self.place(0, 560, aspect: self.landscape).size, .zero)
    }

    func testNegativeAreaGivesAnEmptyRect() throws {
        // The area is the space above the panel, which is negative when the panel is higher than the chat
        XCTAssertEqual(self.place(348, -120, aspect: self.portrait).size, .zero)
        XCTAssertEqual(self.place(-5, 560, aspect: self.portrait).size, .zero)
        XCTAssertEqual(self.place(-5, -5, aspect: self.landscape).size, .zero)
    }

    func testAspectThatIsNotUsableIsReadAsPortrait() throws {
        let expected = self.place(348, 560, aspect: self.portrait)

        XCTAssertEqual(self.place(348, 560, aspect: .nan), expected)
        XCTAssertEqual(self.place(348, 560, aspect: 0), expected)
        XCTAssertEqual(self.place(348, 560, aspect: -1), expected)
        XCTAssertEqual(self.place(348, 560, aspect: .infinity), expected)
    }

    // MARK: - Aspect of the orientation

    func testFrameAspectOfTheOrientations() throws {
        let expected: [(UIInterfaceOrientation, CGFloat)] = [
            (.portrait, 9.0 / 16.0),
            (.portraitUpsideDown, 9.0 / 16.0),
            (.landscapeLeft, 16.0 / 9.0),
            (.landscapeRight, 16.0 / 9.0),
            (.unknown, 9.0 / 16.0)
        ]

        for (orientation, aspect) in expected {
            XCTAssertEqual(VideoMessagePreviewPlacement.frameAspect(for: orientation), aspect, accuracy: 0.0001, "orientation \(orientation.rawValue)")
        }
    }

    func testPlacementAfterARotationSwitchesBetweenThePortraitAndTheLandscapeShape() throws {
        let inPortrait = self.place(390, 600, aspect: VideoMessagePreviewPlacement.frameAspect(for: .portrait))
        let inLandscape = self.place(750, 250, aspect: VideoMessagePreviewPlacement.frameAspect(for: .landscapeLeft))

        XCTAssertLessThan(inPortrait.width, inPortrait.height)
        XCTAssertGreaterThan(inLandscape.width, inLandscape.height)
    }

    // MARK: - Compact recording panel (iPhone 390x844 and 844x390, areas from the estimates in the report)

    func testLandscapePhoneGetsMoreWhenThePanelIsTheHeightOfTheInputbar() throws {
        // Between the navigation bar (32) and the top of the inputbar (317), safe area left and right 47
        let compact = VideoMessagePreviewPlacement.frame(in: CGRect(x: 47, y: 32, width: 750, height: 285), aspect: self.landscape)
        // Between the navigation bar and the top of the big panel of the first version (about 282)
        let big = VideoMessagePreviewPlacement.frame(in: CGRect(x: 47, y: 32, width: 750, height: 250), aspect: self.landscape)

        XCTAssertEqual(compact, CGRect(x: 197, y: 48, width: 450, height: 253))
        XCTAssertEqual(big, CGRect(x: 228, y: 48, width: 388, height: 218))
        XCTAssertGreaterThan(compact.height, big.height)
        self.assertAspect(compact, self.landscape)
    }

    func testPortraitPhoneIsCappedByTheLongestSideWithTheCompactPanel() throws {
        // Between the navigation bar (47 + 44) and the top of the inputbar (758)
        let compact = VideoMessagePreviewPlacement.frame(in: CGRect(x: 0, y: 91, width: 390, height: 667), aspect: self.portrait)

        XCTAssertEqual(compact, CGRect(x: 60, y: 185, width: 270, height: 480))
        XCTAssertLessThanOrEqual(compact.maxY, 758 - 16)
    }
}
