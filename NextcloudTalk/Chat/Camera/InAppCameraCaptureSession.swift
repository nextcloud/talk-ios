//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation
import UIKit

enum InAppCameraError: Error {
    case noCamera
    case captureFailed
}

/// The capture side of the in-app camera: one session for photos and videos. The microphone is only part of the
/// session while a video is recorded, so the audio session of the app is not touched by just showing the camera.
/// The sound is left out when there is no access to the microphone. Every callback is called on the main queue.
final class InAppCameraCaptureSession: NSObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {

    let session = AVCaptureSession()

    /// Photos are taken with the shortest shutter lag, like the camera of the Android app
    static let photoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization = .speed

    var onPhotoCaptured: ((Result<URL, Error>) -> Void)?
    var onRecordingStarted: (() -> Void)?
    var onRecordingFinished: ((Result<URL, Error>) -> Void)?
    var onInterruptionChanged: ((_ isInterrupted: Bool) -> Void)?
    var onRuntimeError: (() -> Void)?

    /// Called when the camera or the abilities of the camera changed, like the flash
    var onConfigurationChanged: (() -> Void)?

    /// Position of the camera in use, only changed on the main queue
    private(set) var cameraPosition: AVCaptureDevice.Position = .back

    var canSwitchCamera: Bool {
        return CameraCaptureHelpers.camera(at: .front) != nil && CameraCaptureHelpers.camera(at: .back) != nil
    }

    /// Whether the camera in use has a flash for photos, or a torch for videos. Read on the session queue,
    /// and handed over to the main queue together with `onConfigurationChanged`.
    private(set) var supportsFlash = false

    private let sessionQueue = DispatchQueue(label: "\(groupIdentifier).inAppCamera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var torchWasEnabled = false
    private let audioSessionRestorer = CaptureAudioSessionRestorer()

    /// The audio session was remembered for a recording and needs to be brought back. Only used on the main queue.
    private var audioSessionNeedsRestore = false

    /// Photos should not get bigger than what the sensors of the common devices give (12 MP, 4:3), like the
    /// system camera does by default. Devices with a bigger sensor would otherwise make files of 48 MP.
    private static let maxPhotoPixelCount = 12_700_000

    override init() {
        super.init()

        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted), name: AVCaptureSession.wasInterruptedNotification, object: self.session)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded), name: AVCaptureSession.interruptionEndedNotification, object: self.session)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError), name: AVCaptureSession.runtimeErrorNotification, object: self.session)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Start and stop

    /// Configures the session on the first call and starts it. `completion` is called on the main queue.
    func start(completion: @escaping (Bool) -> Void) {
        let position = self.cameraPosition

        self.sessionQueue.async {
            if !self.isConfigured {
                self.isConfigured = self.configureSession(position: position)
            }

            guard self.isConfigured else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }

            let supportsFlash = self.readSupportsFlash()

            DispatchQueue.main.async {
                self.supportsFlash = supportsFlash
                self.onConfigurationChanged?()
                completion(true)
            }
        }
    }

    /// Stops the session, a recording that is going on is finished and its file is delivered
    func stop() {
        self.sessionQueue.async {
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }

            self.setTorch(enabled: false)
            self.removeMicrophone()
            self.session.stopRunning()

            DispatchQueue.main.async {
                self.restoreAudioSessionIfNeeded()
            }
        }
    }

    // MARK: - Camera switch

    /// Switches between the front and the back camera, not possible while recording
    func switchCamera() {
        let newPosition: AVCaptureDevice.Position = self.cameraPosition == .front ? .back : .front

        guard CameraCaptureHelpers.camera(at: newPosition) != nil else { return }

        self.cameraPosition = newPosition

        self.sessionQueue.async {
            guard !self.movieOutput.isRecording,
                  let newDevice = CameraCaptureHelpers.camera(at: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice)
            else { return }

            self.session.beginConfiguration()
            self.videoDeviceInput = CameraCaptureHelpers.replaceVideoInput(self.videoDeviceInput, with: newInput, in: self.session)
            self.session.commitConfiguration()

            // The sizes of photos depend on the camera
            self.useLargestPhotoDimensions()

            let supportsFlash = self.readSupportsFlash()

            DispatchQueue.main.async {
                self.supportsFlash = supportsFlash
                self.onConfigurationChanged?()
            }
        }
    }

    // MARK: - Configuration

    private func configureSession(position: AVCaptureDevice.Position) -> Bool {
        guard let camera = CameraCaptureHelpers.camera(at: position) ?? CameraCaptureHelpers.camera(at: position == .front ? .back : .front),
              let cameraInput = try? AVCaptureDeviceInput(device: camera)
        else { return false }

        self.session.beginConfiguration()

        // Needed to add the outputs, the preset for photos is set once they are part of the session
        if self.session.canSetSessionPreset(.high) {
            self.session.sessionPreset = .high
        }

        // Keeps the camera available while the app is shown next to another one on an iPad
        if self.session.isMultitaskingCameraAccessSupported {
            self.session.isMultitaskingCameraAccessEnabled = true
        }

        self.movieOutput.maxRecordedDuration = CMTime(seconds: InAppCameraSupport.maxVideoDuration, preferredTimescale: 600)

        guard self.session.canAddInput(cameraInput), self.session.canAddOutput(self.photoOutput), self.session.canAddOutput(self.movieOutput) else {
            self.session.commitConfiguration()
            return false
        }

        self.session.addInput(cameraInput)
        self.session.addOutput(self.photoOutput)
        self.session.addOutput(self.movieOutput)
        self.videoDeviceInput = cameraInput

        self.session.commitConfiguration()

        // The preset for photos gives the full 4:3 picture of the sensor, the one for videos is set while recording
        self.setPreset(.photo)

        DispatchQueue.main.async {
            self.cameraPosition = cameraInput.device.position
        }

        return true
    }

    /// Needs to be called on the session queue
    private func setPreset(_ preset: AVCaptureSession.Preset) {
        guard self.session.sessionPreset != preset, self.session.canSetSessionPreset(preset) else { return }

        self.session.beginConfiguration()
        self.session.sessionPreset = preset
        self.session.commitConfiguration()

        if preset == .photo {
            self.useLargestPhotoDimensions()
        }
    }

    /// Lets the photo output deliver the biggest photos the active format of the camera can do, up to
    /// `maxPhotoPixelCount`. Needs to be called on the session queue.
    private func useLargestPhotoDimensions() {
        guard let supported = self.videoDeviceInput?.device.activeFormat.supportedMaxPhotoDimensions, !supported.isEmpty else { return }

        func pixelCount(_ dimensions: CMVideoDimensions) -> Int {
            return Int(dimensions.width) * Int(dimensions.height)
        }

        let fitting = supported.filter { pixelCount($0) <= Self.maxPhotoPixelCount }
        let wanted = fitting.max { pixelCount($0) < pixelCount($1) } ?? supported.min { pixelCount($0) < pixelCount($1) }

        guard let wanted, wanted.width != self.photoOutput.maxPhotoDimensions.width || wanted.height != self.photoOutput.maxPhotoDimensions.height else { return }

        self.session.beginConfiguration()
        self.photoOutput.maxPhotoDimensions = wanted
        self.session.commitConfiguration()
    }

    /// Needs to be called on the session queue
    private func readSupportsFlash() -> Bool {
        return !self.photoOutput.supportedFlashModes.isEmpty || (self.videoDeviceInput?.device.hasTorch ?? false)
    }

    /// Needs to be called on the session queue
    private func addMicrophoneIfAllowed() -> Bool {
        guard self.audioDeviceInput == nil,
              AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              let microphone = AVCaptureDevice.default(for: .audio),
              let microphoneInput = try? AVCaptureDeviceInput(device: microphone)
        else { return false }

        self.session.beginConfiguration()
        defer { self.session.commitConfiguration() }

        guard self.session.canAddInput(microphoneInput) else { return false }

        self.session.addInput(microphoneInput)
        self.audioDeviceInput = microphoneInput

        return true
    }

    /// Takes the microphone out of the session again, so the session leaves the audio session alone.
    /// Needs to be called on the session queue.
    private func removeMicrophone() {
        guard let microphoneInput = self.audioDeviceInput else { return }

        self.session.beginConfiguration()
        self.session.removeInput(microphoneInput)
        self.session.commitConfiguration()

        self.audioDeviceInput = nil
    }

    /// Needs to be called on the main queue
    private func restoreAudioSessionIfNeeded() {
        guard self.audioSessionNeedsRestore else { return }

        self.audioSessionNeedsRestore = false
        self.audioSessionRestorer.restore()
    }

    /// The connection is reset by the session whenever the input changes, so the rotation and the mirroring
    /// are set for every capture. Like in the system camera, the picture of the front camera is not mirrored,
    /// while the preview of it is.
    private func prepare(_ connection: AVCaptureConnection?, orientation: UIInterfaceOrientation) {
        guard let connection else { return }

        CameraCaptureHelpers.apply(orientation, to: connection)

        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }

    // MARK: - Photo

    func capturePhoto(flashMode: InAppCameraFlashMode, orientation: UIInterfaceOrientation) {
        self.sessionQueue.async {
            guard self.session.isRunning else {
                DispatchQueue.main.async { self.onPhotoCaptured?(.failure(InAppCameraError.captureFailed)) }
                return
            }

            let settings: AVCapturePhotoSettings

            if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                settings = AVCapturePhotoSettings()
            }

            if self.photoOutput.supportedFlashModes.contains(flashMode.captureFlashMode) {
                settings.flashMode = flashMode.captureFlashMode
            }

            if self.photoOutput.maxPhotoDimensions.width > 0 {
                settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            }

            if Self.photoQualityPrioritization.rawValue <= self.photoOutput.maxPhotoQualityPrioritization.rawValue {
                settings.photoQualityPrioritization = Self.photoQualityPrioritization
            }

            self.prepare(self.photoOutput.connection(with: .video), orientation: orientation)
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // The data is written with the orientation of the connection as EXIF, so the photo is upright everywhere
        guard error == nil, let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async { self.onPhotoCaptured?(.failure(error ?? InAppCameraError.captureFailed)) }
            return
        }

        let isJPEG = self.photoOutput.availablePhotoCodecTypes.contains(.jpeg)
        let url = InAppCameraSupport.makeFileURL(for: .photo(isJPEG: isJPEG))

        do {
            try data.write(to: url, options: .atomic)
            DispatchQueue.main.async { self.onPhotoCaptured?(.success(url)) }
        } catch {
            DispatchQueue.main.async { self.onPhotoCaptured?(.failure(error)) }
        }
    }

    // MARK: - Video

    /// Records with sound if the access to the microphone was allowed, a video without sound is better than no video
    func startRecording(flashMode: InAppCameraFlashMode, orientation: UIInterfaceOrientation) {
        let withSound = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

        if withSound, !self.audioSessionNeedsRestore {
            self.audioSessionRestorer.remember()
            self.audioSessionNeedsRestore = true
        }

        self.sessionQueue.async {
            guard self.session.isRunning, !self.movieOutput.isRecording else {
                DispatchQueue.main.async {
                    self.restoreAudioSessionIfNeeded()
                    self.onRecordingFinished?(.failure(InAppCameraError.captureFailed))
                }
                return
            }

            // The preset for photos can not record videos
            self.setPreset(.high)

            if withSound {
                _ = self.addMicrophoneIfAllowed()
            }

            self.prepare(self.movieOutput.connection(with: .video), orientation: orientation)
            self.setTorch(enabled: flashMode == .on)

            self.movieOutput.startRecording(to: InAppCameraSupport.makeFileURL(for: .video), recordingDelegate: self)
        }
    }

    func stopRecording() {
        self.sessionQueue.async {
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
        }
    }

    /// Needs to be called on the session queue
    private func setTorch(enabled: Bool) {
        if !enabled && !self.torchWasEnabled {
            return
        }

        guard let device = self.videoDeviceInput?.device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }

        device.torchMode = enabled ? .on : .off
        device.unlockForConfiguration()

        self.torchWasEnabled = enabled
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async { self.onRecordingStarted?() }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        // The recording can end with an error although the file is complete, like when the time is up
        let finishedSuccessfully = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)

        self.sessionQueue.async {
            self.setTorch(enabled: false)
            self.removeMicrophone()
            self.setPreset(.photo)

            DispatchQueue.main.async {
                self.restoreAudioSessionIfNeeded()
            }
        }

        if finishedSuccessfully {
            DispatchQueue.main.async { self.onRecordingFinished?(.success(outputFileURL)) }
        } else {
            try? FileManager.default.removeItem(at: outputFileURL)
            DispatchQueue.main.async { self.onRecordingFinished?(.failure(error ?? InAppCameraError.captureFailed)) }
        }
    }

    // MARK: - Notifications

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        if let reasonValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int,
           AVCaptureSession.InterruptionReason(rawValue: reasonValue) == .audioDeviceInUseByAnotherClient {
            self.audioSessionRestorer.audioDeviceTakenByAnotherClient = true
        }

        DispatchQueue.main.async { self.onInterruptionChanged?(true) }
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        DispatchQueue.main.async { self.onInterruptionChanged?(false) }
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError

        // After a reset of the media services the session needs to be started again
        if error?.code == .mediaServicesWereReset {
            self.sessionQueue.async {
                if !self.session.isRunning {
                    self.session.startRunning()
                }
            }
        }

        DispatchQueue.main.async { self.onRuntimeError?() }
    }
}
