//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation
import UIKit

/// Code that is shared by everything in the app that captures with the camera: video messages and the in-app camera
enum CameraCaptureHelpers {

    /// The camera that is used for a position, if the device has one
    static func camera(at position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    /// Replaces the video input of a session with another one, the session needs to be in a configuration block.
    /// Returns the input that is part of the session afterwards, which is the old one when the new one can not be added.
    static func replaceVideoInput(_ oldInput: AVCaptureDeviceInput?, with newInput: AVCaptureDeviceInput, in session: AVCaptureSession) -> AVCaptureDeviceInput? {
        if let oldInput {
            session.removeInput(oldInput)
        }

        if session.canAddInput(newInput) {
            session.addInput(newInput)
            return newInput
        }

        if let oldInput, session.canAddInput(oldInput) {
            session.addInput(oldInput)
        }

        return oldInput
    }

    /// Rotates the frames of a connection so they are upright in the given orientation of the interface
    static func apply(_ orientation: UIInterfaceOrientation, to connection: AVCaptureConnection) {
        if #available(iOS 17.0, *) {
            let angle: CGFloat

            switch orientation {
            case .landscapeRight: angle = 0
            case .landscapeLeft: angle = 180
            case .portraitUpsideDown: angle = 270
            default: angle = 90
            }

            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        } else if connection.isVideoOrientationSupported,
                  let videoOrientation = AVCaptureVideoOrientation(rawValue: orientation == .unknown ? UIInterfaceOrientation.portrait.rawValue : orientation.rawValue) {
            connection.videoOrientation = videoOrientation
        }
    }

    /// The orientation of the interface a view is shown in, portrait as long as that is not known
    static func interfaceOrientation(of view: UIView?) -> UIInterfaceOrientation {
        let orientation = view?.window?.windowScene?.interfaceOrientation ?? .portrait

        return orientation == .unknown ? .portrait : orientation
    }
}

/// Live preview of a capture session, which follows the orientation of the interface
class CameraPreviewView: UIView {

    let previewLayer: AVCaptureVideoPreviewLayer

    /// The orientation the frames of the preview are rotated to
    var interfaceOrientation: UIInterfaceOrientation {
        didSet {
            if oldValue != self.interfaceOrientation {
                self.setNeedsLayout()
            }
        }
    }

    init(session: AVCaptureSession, interfaceOrientation: UIInterfaceOrientation) {
        self.interfaceOrientation = interfaceOrientation
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)

        super.init(frame: .zero)

        self.backgroundColor = .black
        self.clipsToBounds = true

        self.previewLayer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(self.previewLayer)

        // The session is set up on another queue, so the layer has no connection to rotate before it ran
        NotificationCenter.default.addObserver(self, selector: #selector(sessionDidStartRunning), name: AVCaptureSession.didStartRunningNotification, object: session)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func sessionDidStartRunning() {
        DispatchQueue.main.async { self.setNeedsLayout() }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.previewLayer.frame = self.bounds

        if let connection = self.previewLayer.connection {
            CameraCaptureHelpers.apply(self.interfaceOrientation, to: connection)
        }
    }
}

/// A capture session changes the shared audio session when a microphone is part of it. This remembers
/// the audio session from before, so voice messages, audio playback and calls are not affected afterwards.
final class CaptureAudioSessionRestorer {

    private var previousCategory: AVAudioSession.Category?
    private var previousMode: AVAudioSession.Mode?
    private var previousOptions: AVAudioSession.CategoryOptions?

    /// Set when another app took the audio device, the audio session is not ours to touch then
    var audioDeviceTakenByAnotherClient = false

    /// Needs to be called before the capture session starts
    func remember() {
        let audioSession = AVAudioSession.sharedInstance()
        self.previousCategory = audioSession.category
        self.previousMode = audioSession.mode
        self.previousOptions = audioSession.categoryOptions
    }

    /// Deactivates the audio session and brings back the category from before
    func restore() {
        // During a call the audio session belongs to the call, and so it does when another app took the device
        guard !self.audioSessionIsInUseElsewhere else {
            self.previousMode = nil
            self.previousOptions = nil
            return
        }

        let audioSession = AVAudioSession.sharedInstance()

        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)

        if let category = self.previousCategory,
           let mode = self.previousMode,
           let options = self.previousOptions {
            try? audioSession.setCategory(category, mode: mode, options: options)
        }

        self.previousCategory = nil
        self.previousMode = nil
        self.previousOptions = nil
    }

    private var audioSessionIsInUseElsewhere: Bool {
        return self.audioDeviceTakenByAnotherClient
            || NCRoomsManager.shared.callViewController != nil
            || !CallKitManager.sharedInstance().calls.isEmpty
    }
}
