//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation
import UIKit
import XCTest
@testable import NextcloudTalk

final class UnitInAppCameraTest: XCTestCase {

    // MARK: - Flash mode

    func testFlashModeKeepsTheValuesOfTheSystemCamera() throws {
        XCTAssertEqual(InAppCameraFlashMode.off.rawValue, UIImagePickerController.CameraFlashMode.off.rawValue)
        XCTAssertEqual(InAppCameraFlashMode.auto.rawValue, UIImagePickerController.CameraFlashMode.auto.rawValue)
        XCTAssertEqual(InAppCameraFlashMode.on.rawValue, UIImagePickerController.CameraFlashMode.on.rawValue)
    }

    func testFlashModeFromStoredValue() throws {
        // Nothing stored is read as 0 by NCUserDefaults, which is auto
        XCTAssertEqual(InAppCameraFlashMode(storedValue: 0), .auto)
        XCTAssertEqual(InAppCameraFlashMode(storedValue: -1), .off)
        XCTAssertEqual(InAppCameraFlashMode(storedValue: 1), .on)
        XCTAssertEqual(InAppCameraFlashMode(storedValue: 42), .off)
    }

    func testFlashModeCyclesThroughAllModes() throws {
        XCTAssertEqual(InAppCameraFlashMode.off.next, .auto)
        XCTAssertEqual(InAppCameraFlashMode.auto.next, .on)
        XCTAssertEqual(InAppCameraFlashMode.on.next, .off)
    }

    func testFlashModeMapsToCaptureFlashMode() throws {
        XCTAssertEqual(InAppCameraFlashMode.off.captureFlashMode, .off)
        XCTAssertEqual(InAppCameraFlashMode.auto.captureFlashMode, .auto)
        XCTAssertEqual(InAppCameraFlashMode.on.captureFlashMode, .on)
    }

    func testFlashModesHaveDifferentSymbols() throws {
        let symbols = Set(InAppCameraFlashMode.allCases.map { $0.symbolName })
        XCTAssertEqual(symbols.count, InAppCameraFlashMode.allCases.count)
    }

    // MARK: - Files

    func testFileURLsAreInTheGivenDirectoryAndHaveTheExtensionOfTheKind() throws {
        let uuid = UUID()

        let photo = InAppCameraSupport.makeFileURL(for: .photo(isJPEG: true), directory: "/tmp/test", uuid: uuid)
        XCTAssertEqual(photo.path, "/tmp/test/in-app-camera-\(uuid.uuidString).jpg")

        let heic = InAppCameraSupport.makeFileURL(for: .photo(isJPEG: false), directory: "/tmp/test", uuid: uuid)
        XCTAssertEqual(heic.pathExtension, "heic")

        let video = InAppCameraSupport.makeFileURL(for: .video, directory: "/tmp/test", uuid: uuid)
        XCTAssertEqual(video.pathExtension, "mov")
    }

    func testEveryFileURLIsNew() throws {
        let first = InAppCameraSupport.makeFileURL(for: .video)
        let second = InAppCameraSupport.makeFileURL(for: .video)

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.path.hasPrefix(NSTemporaryDirectory()) || first.path.hasPrefix(URL(fileURLWithPath: NSTemporaryDirectory()).path))
    }

    // MARK: - Duration

    func testFormattedDuration() throws {
        XCTAssertEqual(InAppCameraSupport.formattedDuration(0), "0:00")
        XCTAssertEqual(InAppCameraSupport.formattedDuration(7.9), "0:07")
        XCTAssertEqual(InAppCameraSupport.formattedDuration(60), "1:00")
        XCTAssertEqual(InAppCameraSupport.formattedDuration(754), "12:34")
        XCTAssertEqual(InAppCameraSupport.formattedDuration(3723), "1:02:03")
        XCTAssertEqual(InAppCameraSupport.formattedDuration(-5), "0:00")
    }

    // MARK: - Orientation

    func testCaptureOrientationFollowsTheDevice() throws {
        XCTAssertEqual(InAppCameraSupport.captureOrientation(device: .portrait, interface: .landscapeLeft), .portrait)
        XCTAssertEqual(InAppCameraSupport.captureOrientation(device: .portraitUpsideDown, interface: .portrait), .portraitUpsideDown)
        // The interface is rotated the other way round than the device in landscape
        XCTAssertEqual(InAppCameraSupport.captureOrientation(device: .landscapeLeft, interface: .portrait), .landscapeRight)
        XCTAssertEqual(InAppCameraSupport.captureOrientation(device: .landscapeRight, interface: .portrait), .landscapeLeft)
    }

    func testCaptureOrientationFallsBackToTheInterface() throws {
        XCTAssertEqual(InAppCameraSupport.captureOrientation(device: .faceUp, interface: .landscapeRight), .landscapeRight)
        XCTAssertEqual(InAppCameraSupport.captureOrientation(device: .unknown, interface: .landscapeLeft), .landscapeLeft)
        XCTAssertEqual(InAppCameraSupport.captureOrientation(device: .faceDown, interface: .unknown), .portrait)
    }

    func testHeldOrientationKeepsTheLastOneWhenTheDeviceLiesFlat() throws {
        XCTAssertEqual(InAppCameraSupport.heldOrientation(current: .landscapeLeft, last: .portrait), .landscapeLeft)
        XCTAssertEqual(InAppCameraSupport.heldOrientation(current: .portraitUpsideDown, last: .landscapeRight), .portraitUpsideDown)
        XCTAssertEqual(InAppCameraSupport.heldOrientation(current: .faceUp, last: .landscapeLeft), .landscapeLeft)
        XCTAssertEqual(InAppCameraSupport.heldOrientation(current: .faceDown, last: .landscapeRight), .landscapeRight)
        XCTAssertEqual(InAppCameraSupport.heldOrientation(current: .unknown, last: .portraitUpsideDown), .portraitUpsideDown)
        XCTAssertEqual(InAppCameraSupport.heldOrientation(current: .faceUp, last: .unknown), .unknown)
    }

    func testFlatDeviceCapturesInTheLastHeldOrientationOnThePhone() throws {
        // Held in landscape, then laid flat: the interface is portrait, the photo still is landscape
        let held = InAppCameraSupport.heldOrientation(current: .faceUp, last: .landscapeLeft)

        XCTAssertEqual(InAppCameraSupport.captureOrientation(device: held, interface: .portrait), .landscapeRight)
        XCTAssertEqual(InAppCameraSupport.iconRotationDegrees(device: held, interface: .portrait), 90)
    }

    // MARK: - Layout along the body

    func testScreenEdgeOfTheBodyFollowsTheInterface() throws {
        XCTAssertEqual(InAppCameraSupport.screenEdge(ofBodyEdge: .bottom, interface: .portrait), .bottom)
        XCTAssertEqual(InAppCameraSupport.screenEdge(ofBodyEdge: .top, interface: .portrait), .top)
        XCTAssertEqual(InAppCameraSupport.screenEdge(ofBodyEdge: .bottom, interface: .unknown), .bottom)
        XCTAssertEqual(InAppCameraSupport.screenEdge(ofBodyEdge: .bottom, interface: .portraitUpsideDown), .top)
        XCTAssertEqual(InAppCameraSupport.screenEdge(ofBodyEdge: .left, interface: .portraitUpsideDown), .right)
    }

    func testScreenEdgeOfTheBodyInLandscape() throws {
        // The home button is at the bottom of the body, in .landscapeLeft it is on the left of the screen
        XCTAssertEqual(InAppCameraSupport.screenEdge(ofBodyEdge: .bottom, interface: .landscapeLeft), .left)
        XCTAssertEqual(InAppCameraSupport.screenEdge(ofBodyEdge: .top, interface: .landscapeLeft), .right)
        XCTAssertEqual(InAppCameraSupport.screenEdge(ofBodyEdge: .left, interface: .landscapeLeft), .top)
        XCTAssertEqual(InAppCameraSupport.screenEdge(ofBodyEdge: .right, interface: .landscapeLeft), .bottom)

        XCTAssertEqual(InAppCameraSupport.screenEdge(ofBodyEdge: .bottom, interface: .landscapeRight), .right)
        XCTAssertEqual(InAppCameraSupport.screenEdge(ofBodyEdge: .top, interface: .landscapeRight), .left)
        XCTAssertEqual(InAppCameraSupport.screenEdge(ofBodyEdge: .left, interface: .landscapeRight), .bottom)
        XCTAssertEqual(InAppCameraSupport.screenEdge(ofBodyEdge: .right, interface: .landscapeRight), .top)
    }

    func testOutwardDirectionOfAnEdge() throws {
        XCTAssertEqual(InAppCameraEdge.top.outwardDirection.dy, -1)
        XCTAssertEqual(InAppCameraEdge.top.outwardDirection.dx, 0)
        XCTAssertEqual(InAppCameraEdge.bottom.outwardDirection.dy, 1)
        XCTAssertEqual(InAppCameraEdge.left.outwardDirection.dx, -1)
        XCTAssertEqual(InAppCameraEdge.right.outwardDirection.dx, 1)
        XCTAssertEqual(InAppCameraEdge.right.outwardDirection.dy, 0)
    }

    // MARK: - Rotation of the icons

    func testIconRotationOnThePhoneInPortrait() throws {
        XCTAssertEqual(InAppCameraSupport.iconRotationDegrees(device: .portrait, interface: .portrait), 0)
        // The device is turned clockwise (home button on the left), so the icons turn back counterclockwise
        XCTAssertEqual(InAppCameraSupport.iconRotationDegrees(device: .landscapeRight, interface: .portrait), 270)
        XCTAssertEqual(InAppCameraSupport.iconRotationDegrees(device: .landscapeLeft, interface: .portrait), 90)
        XCTAssertEqual(InAppCameraSupport.iconRotationDegrees(device: .portraitUpsideDown, interface: .portrait), 180)
    }

    func testIconRotationIsRelativeToTheInterface() throws {
        // The interface turned with the device, so nothing is left to turn
        XCTAssertEqual(InAppCameraSupport.iconRotationDegrees(device: .landscapeRight, interface: .landscapeLeft), 0)
        XCTAssertEqual(InAppCameraSupport.iconRotationDegrees(device: .landscapeLeft, interface: .landscapeRight), 0)
        XCTAssertEqual(InAppCameraSupport.iconRotationDegrees(device: .portraitUpsideDown, interface: .portraitUpsideDown), 0)
        XCTAssertEqual(InAppCameraSupport.iconRotationDegrees(device: .portrait, interface: .landscapeLeft), 90)
        XCTAssertEqual(InAppCameraSupport.iconRotationDegrees(device: .portrait, interface: .landscapeRight), 270)
    }

    func testIconRotationIsUnchangedWithoutUsableDeviceOrientation() throws {
        XCTAssertNil(InAppCameraSupport.iconRotationDegrees(device: .faceUp, interface: .portrait))
        XCTAssertNil(InAppCameraSupport.iconRotationDegrees(device: .faceDown, interface: .landscapeLeft))
        XCTAssertNil(InAppCameraSupport.iconRotationDegrees(device: .unknown, interface: .portrait))
    }

    func testShortestRotationTarget() throws {
        // 0 to 270 goes through -90, not around the circle
        XCTAssertEqual(InAppCameraSupport.shortestRotationTarget(current: 0, target: 270), -90)
        XCTAssertEqual(InAppCameraSupport.shortestRotationTarget(current: -90, target: 0), 0)
        XCTAssertEqual(InAppCameraSupport.shortestRotationTarget(current: 0, target: 90), 90)
        XCTAssertEqual(InAppCameraSupport.shortestRotationTarget(current: 90, target: 270), 270)
        XCTAssertEqual(InAppCameraSupport.shortestRotationTarget(current: -90, target: 90), 90)
        XCTAssertEqual(InAppCameraSupport.shortestRotationTarget(current: 90, target: 0), 0)
        XCTAssertEqual(InAppCameraSupport.shortestRotationTarget(current: 0, target: 0), 0)
        // Half a turn has no short way, it is clockwise
        XCTAssertEqual(InAppCameraSupport.shortestRotationTarget(current: 0, target: 180), 180)
    }

    func testShortestRotationTargetFromAnAngleThatWentAround() throws {
        XCTAssertEqual(InAppCameraSupport.shortestRotationTarget(current: -270, target: 0), -360)
        XCTAssertEqual(InAppCameraSupport.shortestRotationTarget(current: 270, target: 0), 360)
        XCTAssertEqual(InAppCameraSupport.shortestRotationTarget(current: 360, target: 270), 270)
    }
}
