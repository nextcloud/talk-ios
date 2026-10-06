//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation
import Foundation
import UIKit

/// The flash mode of the in-app camera. The raw values are the ones of `UIImagePickerController.CameraFlashMode`,
/// so the mode that is stored in `NCUserDefaults` is shared with the camera of the system.
enum InAppCameraFlashMode: Int, CaseIterable {
    case off = -1
    case auto = 0
    case on = 1

    /// The stored value, a value that is not known switches the flash off like the system camera does here
    init(storedValue: Int) {
        self = InAppCameraFlashMode(rawValue: storedValue) ?? .off
    }

    /// The mode a tap on the flash button switches to
    var next: InAppCameraFlashMode {
        switch self {
        case .off: return .auto
        case .auto: return .on
        case .on: return .off
        }
    }

    var captureFlashMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off: return .off
        case .auto: return .auto
        case .on: return .on
        }
    }

    var symbolName: String {
        switch self {
        case .off: return "bolt.slash.fill"
        case .auto: return "bolt.badge.a.fill"
        case .on: return "bolt.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .off: return NSLocalizedString("Flash off", comment: "")
        case .auto: return NSLocalizedString("Flash auto", comment: "")
        case .on: return NSLocalizedString("Flash on", comment: "")
        }
    }
}

enum InAppCameraMediaKind {
    case photo(isJPEG: Bool)
    case video

    var fileExtension: String {
        switch self {
        case .photo(let isJPEG): return isJPEG ? "jpg" : "heic"
        case .video: return "mov"
        }
    }
}

/// An edge of the body of the device or of the screen, in clockwise order
enum InAppCameraEdge: Int {
    case top = 0
    case right = 1
    case bottom = 2
    case left = 3

    /// The direction that points out of the screen over this edge, as steps in x and y (y grows downwards)
    var outwardDirection: (dx: Int, dy: Int) {
        switch self {
        case .top: return (0, -1)
        case .right: return (1, 0)
        case .bottom: return (0, 1)
        case .left: return (-1, 0)
        }
    }
}

enum InAppCameraSupport {

    /// A recording ends by itself after this time
    static let maxVideoDuration: TimeInterval = 300

    /// A new file in the temporary directory. Every capture has a file of its own, the owner of the file is
    /// whoever receives it from the camera.
    static func makeFileURL(for kind: InAppCameraMediaKind, directory: String = NSTemporaryDirectory(), uuid: UUID = UUID()) -> URL {
        return URL(fileURLWithPath: directory)
            .appendingPathComponent("in-app-camera-\(uuid.uuidString).\(kind.fileExtension)")
    }

    /// The orientation to capture in. It is the one the device is held in, so a photo is upright even when the
    /// rotation of the interface is locked. Without a usable device orientation (flat on a table) it is the one
    /// of the interface.
    static func captureOrientation(device: UIDeviceOrientation, interface: UIInterfaceOrientation) -> UIInterfaceOrientation {
        switch device {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        // The device and the interface are rotated the other way round in landscape
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        default: return interface == .unknown ? .portrait : interface
        }
    }

    /// The orientation the device is held in: the current one, or the last one that was usable while the device
    /// lies flat or has no orientation. The interface can not stand in for it when it is locked to portrait.
    static func heldOrientation(current: UIDeviceOrientation, last: UIDeviceOrientation) -> UIDeviceOrientation {
        switch current {
        case .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight: return current
        default: return last
        }
    }

    /// How often the body of the device is turned clockwise against the interface: 0 in portrait, 1 with the home
    /// button on the left (`.landscapeLeft`), 2 upside down, 3 with the home button on the right
    static func interfaceQuarterTurns(_ interface: UIInterfaceOrientation) -> Int {
        switch interface {
        case .landscapeLeft: return 1
        case .portraitUpsideDown: return 2
        case .landscapeRight: return 3
        default: return 0
        }
    }

    /// The edge of the screen an edge of the body of the device (as in portrait, with the home button at the bottom)
    /// is at, when the interface has the given orientation
    static func screenEdge(ofBodyEdge edge: InAppCameraEdge, interface: UIInterfaceOrientation) -> InAppCameraEdge {
        return InAppCameraEdge(rawValue: (edge.rawValue + self.interfaceQuarterTurns(interface)) % 4) ?? edge
    }

    /// The angle in degrees (0, 90, 180 or 270, clockwise) the icons of the camera are rotated by, so they are upright
    /// for the person who holds the device. It is the rotation of the device against the interface.
    /// Nil when the device has no usable orientation (flat on a table), the icons stay as they are then.
    static func iconRotationDegrees(device: UIDeviceOrientation, interface: UIInterfaceOrientation) -> Int? {
        let deviceTurns: Int

        switch device {
        case .portrait: deviceTurns = 0
        // The home button is on the left, so the device is turned clockwise
        case .landscapeRight: deviceTurns = 1
        case .portraitUpsideDown: deviceTurns = 2
        case .landscapeLeft: deviceTurns = 3
        default: return nil
        }

        return (((self.interfaceQuarterTurns(interface) - deviceTurns) % 4) + 4) % 4 * 90
    }

    /// The angle to animate the icons to, an angle that looks the same as the target but is the shortest way from the
    /// current one. So 0 to 270 goes through -90 and not around the full circle.
    static func shortestRotationTarget(current: Double, target: Int) -> Double {
        var delta = (Double(target) - current).truncatingRemainder(dividingBy: 360)

        if delta > 180 {
            delta -= 360
        } else if delta <= -180 {
            delta += 360
        }

        return current + delta
    }

    /// The time of a recording like "0:07" or "12:34", or "1:02:03" after an hour
    static func formattedDuration(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }
}
