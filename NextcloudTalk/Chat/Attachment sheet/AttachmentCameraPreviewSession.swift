//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation

/// A light capture session for the live camera tile of the attachment sheet: video only, no audio, no output.
/// The camera of the chat has its own session, this one is stopped before the camera is opened.
///
/// The session is started and stopped on a queue of its own, as `startRunning()` blocks.
final class AttachmentCameraPreviewSession {

    let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "\(Bundle.main.bundleIdentifier ?? "talk").attachmentSheet.cameraPreview")
    private var isConfigured = false

    /// Whether the user allowed the camera already. The permission is never asked for here, only when the camera is opened.
    static var isCameraAuthorized: Bool {
        return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    /// The camera is in use during a call
    @MainActor
    static var isCameraBusyWithCall: Bool {
        return NCRoomsManager.shared.callViewController != nil
    }

    func start() {
        self.queue.async { [weak self] in
            guard let self, self.configureIfNeeded() else { return }

            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    /// - Parameter completion: Called on the main queue once the session is stopped
    func stop(completion: (() -> Void)? = nil) {
        // Strong on purpose: the session needs to be stopped even if its owner is gone by the time the queue gets to it
        self.queue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }

            if let completion {
                DispatchQueue.main.async(execute: completion)
            }
        }
    }

    /// Needs to run on `queue`
    private func configureIfNeeded() -> Bool {
        if self.isConfigured {
            return true
        }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera)
        else { return false }

        self.session.beginConfiguration()
        defer { self.session.commitConfiguration() }

        if self.session.canSetSessionPreset(.medium) {
            self.session.sessionPreset = .medium
        }

        guard self.session.canAddInput(input) else { return false }
        self.session.addInput(input)

        self.isConfigured = true
        return true
    }
}
