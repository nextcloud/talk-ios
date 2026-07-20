//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

#if targetEnvironment(simulator)

import Foundation
import UIKit
import WebRTC

/// Video capturer for the simulator, where no camera is available.
/// Generates a test pattern (color slowly cycling through the hue spectrum),
/// so video can still be debugged on the simulator. The frames are rotated
/// based on the simulated device orientation, like a real camera would do.
class SimulatorVideoCapturer: RTCVideoCapturer {

    private static let frameWidth = 640
    private static let frameHeight = 480
    private static let framesPerSecond = 15

    // One full pass through the hue spectrum every 60 seconds
    private static let framesPerHueCycle = framesPerSecond * 60

    private let captureQueue = DispatchQueue(label: "simulatorvideocapturer")
    private var timer: DispatchSourceTimer?
    private var frameNumber = 0
    private var videoRotation = RTCVideoRotation._90

    deinit {
        timer?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    public func startCapture() {
        DispatchQueue.main.async {
            // Orientation notifications are already generated app-wide, see AppDelegate
            NotificationCenter.default.addObserver(self, selector: #selector(self.deviceOrientationDidChangeNotification), name: UIDevice.orientationDidChangeNotification, object: nil)
            self.updateVideoRotation()
        }

        captureQueue.async {
            guard self.timer == nil else { return }

            let timer = DispatchSource.makeTimerSource(queue: self.captureQueue)
            timer.schedule(deadline: .now(), repeating: 1.0 / Double(Self.framesPerSecond))
            timer.setEventHandler { [weak self] in
                self?.captureNextFrame()
            }
            timer.activate()

            self.timer = timer
        }
    }

    @objc private func deviceOrientationDidChangeNotification() {
        self.updateVideoRotation()
    }

    private func updateVideoRotation() {
        let rotation: RTCVideoRotation

        switch UIDevice.current.orientation {
        case .portrait:
            rotation = ._90
        case .portraitUpsideDown:
            rotation = ._270
        case .landscapeLeft:
            rotation = ._0
        case .landscapeRight:
            rotation = ._180
        default:
            // Keep the current rotation for face up/down and unknown orientations
            return
        }

        captureQueue.async {
            self.videoRotation = rotation
        }
    }

    public func stopCapture() {
        captureQueue.async {
            self.timer?.cancel()
            self.timer = nil
        }
    }

    private func captureNextFrame() {
        var newPixelBuffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]] as CFDictionary
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Self.frameWidth, Self.frameHeight, kCVPixelFormatType_32BGRA, attributes, &newPixelBuffer)

        guard status == kCVReturnSuccess, let pixelBuffer = newPixelBuffer else { return }

        self.frameNumber += 1
        self.drawTestPattern(into: pixelBuffer)

        let timeStampNs = CACurrentMediaTime() * Float64(NSEC_PER_SEC)
        let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let videoFrame = RTCVideoFrame(buffer: rtcPixelBuffer, rotation: videoRotation, timeStampNs: Int64(timeStampNs))

        self.delegate?.capturer(self, didCapture: videoFrame)
    }

    private func drawTestPattern(into pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer),
                                      width: Self.frameWidth,
                                      height: Self.frameHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }

        let bounds = CGRect(x: 0, y: 0, width: Self.frameWidth, height: Self.frameHeight)
        let hue = CGFloat(frameNumber % Self.framesPerHueCycle) / CGFloat(Self.framesPerHueCycle)

        context.setFillColor(UIColor(hue: hue, saturation: 1, brightness: 1, alpha: 1).cgColor)
        context.fill(bounds)
    }
}

#endif
