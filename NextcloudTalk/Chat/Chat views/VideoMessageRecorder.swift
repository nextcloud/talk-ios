//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation
import UIKit

/// Records a short video with sound into an MP4 file (H.264 / AAC), in the orientation of the interface it started in.
///
/// This deliberately does not use `AVCaptureMovieFileOutput`: removing the video input of the session to
/// switch between the front and the back camera tears down the connection of that output, which ends
/// the recording. With `AVCaptureVideoDataOutput` and `AVCaptureAudioDataOutput` feeding an
/// `AVAssetWriter`, the writer is not part of the capture graph and keeps running while the camera is swapped.
final class VideoMessageRecorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {

    /// A video message ends automatically after this time
    static let maxDuration: TimeInterval = 60

    /// Pixel size of the longer and the shorter side of the video, from the 1280x720 capture preset
    private static let videoLongSide = 1280
    private static let videoShortSide = 720

    /// Orientation of the interface when the recording started, it is fixed for the whole recording
    let interfaceOrientation: UIInterfaceOrientation

    var isLandscape: Bool {
        return self.interfaceOrientation.isLandscape
    }

    let session = AVCaptureSession()

    /// Called on the main queue when the recording can not go on (session interrupted, runtime error)
    var onFailure: (() -> Void)?

    /// Time of the start of the recording, only set on the main queue
    private(set) var startDate: Date?

    /// Position of the camera in use, only changed on the main queue
    private(set) var cameraPosition: AVCaptureDevice.Position = .front

    var elapsed: TimeInterval {
        guard let startDate else { return 0 }
        return Date().timeIntervalSince(startDate)
    }

    let outputURL: URL

    // Session configuration and start/stop can block, so they are kept off the main queue
    private let sessionQueue = DispatchQueue(label: "\(groupIdentifier).videoMessage.session")

    // Sample buffers of both outputs arrive on this queue, as does all access to the writer
    private let sampleQueue = DispatchQueue(label: "\(groupIdentifier).videoMessage.samples")

    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?

    private var writer: AVAssetWriter?
    private var writerVideoInput: AVAssetWriterInput?
    private var writerAudioInput: AVAssetWriterInput?
    private var sessionStartTime: CMTime?
    private var isWriting = false

    // Brings back the audio session, as the capture session changes it
    private let audioSessionRestorer = CaptureAudioSessionRestorer()

    init(interfaceOrientation: UIInterfaceOrientation) {
        self.interfaceOrientation = interfaceOrientation

        // Every recorder has a file of its own, as the file of a previous one might still be finished
        self.outputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("video-message-recording-\(UUID().uuidString).mp4")

        super.init()

        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted), name: AVCaptureSession.wasInterruptedNotification, object: self.session)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError), name: AVCaptureSession.runtimeErrorNotification, object: self.session)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Start and stop

    /// Starts the camera and the recording. `completion` is called on the main queue.
    func start(completion: @escaping (Bool) -> Void) {
        self.audioSessionRestorer.remember()

        let initialPosition = self.cameraPosition

        self.sessionQueue.async {
            guard self.configureSession(position: initialPosition),
                  self.sampleQueue.sync(execute: { self.prepareWriter() })
            else {
                DispatchQueue.main.async {
                    self.audioSessionRestorer.restore()
                    completion(false)
                }
                return
            }

            self.session.startRunning()

            DispatchQueue.main.async {
                self.startDate = Date()
                completion(true)
            }
        }
    }

    /// Stops the camera and finishes the file. `completion` is called on the main queue, with the
    /// file when `keepFile` is set and the file is complete.
    func stop(keepFile: Bool, completion: ((URL?) -> Void)? = nil) {
        self.sessionQueue.async {
            self.session.stopRunning()

            self.sampleQueue.async {
                self.isWriting = false

                let finish: (URL?) -> Void = { url in
                    DispatchQueue.main.async {
                        self.audioSessionRestorer.restore()
                        completion?(url)
                    }
                }

                guard let writer = self.writer else {
                    finish(nil)
                    return
                }

                self.writer = nil

                guard keepFile, writer.status == .writing else {
                    // Cancelling is only allowed once the writer has started, which needs a first frame
                    if writer.status == .writing {
                        writer.cancelWriting()
                    }

                    try? FileManager.default.removeItem(at: self.outputURL)
                    finish(nil)
                    return
                }

                self.writerVideoInput?.markAsFinished()
                self.writerAudioInput?.markAsFinished()

                writer.finishWriting {
                    if writer.status == .completed {
                        finish(self.outputURL)
                    } else {
                        try? FileManager.default.removeItem(at: self.outputURL)
                        finish(nil)
                    }
                }
            }
        }
    }

    // MARK: - Camera switch

    /// Switches between the front and the back camera, without interrupting the recording
    func switchCamera() {
        let newPosition: AVCaptureDevice.Position = self.cameraPosition == .front ? .back : .front

        guard CameraCaptureHelpers.camera(at: newPosition) != nil else { return }

        self.cameraPosition = newPosition

        self.sessionQueue.async {
            guard let newDevice = CameraCaptureHelpers.camera(at: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice)
            else { return }

            self.session.beginConfiguration()

            self.videoDeviceInput = CameraCaptureHelpers.replaceVideoInput(self.videoDeviceInput, with: newInput, in: self.session)

            // The connection of the output is created again with the new input
            self.configureVideoConnection()

            self.session.commitConfiguration()
        }
    }

    var canSwitchCamera: Bool {
        return CameraCaptureHelpers.camera(at: .front) != nil && CameraCaptureHelpers.camera(at: .back) != nil
    }

    // MARK: - Configuration

    private func configureSession(position: AVCaptureDevice.Position) -> Bool {
        guard let camera = CameraCaptureHelpers.camera(at: position) ?? CameraCaptureHelpers.camera(at: position == .front ? .back : .front),
              let microphone = AVCaptureDevice.default(for: .audio),
              let cameraInput = try? AVCaptureDeviceInput(device: camera),
              let microphoneInput = try? AVCaptureDeviceInput(device: microphone)
        else { return false }

        self.session.beginConfiguration()

        if self.session.canSetSessionPreset(.hd1280x720) {
            self.session.sessionPreset = .hd1280x720
        }

        // Keeps the camera available while the app is shown next to another one on an iPad
        if self.session.isMultitaskingCameraAccessSupported {
            self.session.isMultitaskingCameraAccessEnabled = true
        }

        self.videoOutput.alwaysDiscardsLateVideoFrames = true
        self.videoOutput.setSampleBufferDelegate(self, queue: self.sampleQueue)
        self.audioOutput.setSampleBufferDelegate(self, queue: self.sampleQueue)

        guard self.session.canAddInput(cameraInput), self.session.canAddInput(microphoneInput),
              self.session.canAddOutput(self.videoOutput), self.session.canAddOutput(self.audioOutput)
        else {
            self.session.commitConfiguration()
            return false
        }

        self.session.addInput(cameraInput)
        self.session.addInput(microphoneInput)
        self.session.addOutput(self.videoOutput)
        self.session.addOutput(self.audioOutput)
        self.videoDeviceInput = cameraInput

        self.configureVideoConnection()

        self.session.commitConfiguration()

        return true
    }

    /// The connection is reset by the session whenever the input changes, so this needs to run after every
    /// change of the camera. The recording is not mirrored, like in the system camera, while the preview of
    /// the front camera is.
    private func configureVideoConnection() {
        guard let connection = self.videoOutput.connection(with: .video) else { return }

        CameraCaptureHelpers.apply(self.interfaceOrientation, to: connection)

        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }

    /// Needs to be called on the sample queue
    private func prepareWriter() -> Bool {
        try? FileManager.default.removeItem(at: self.outputURL)

        guard let writer = try? AVAssetWriter(outputURL: self.outputURL, fileType: .mp4) else { return false }

        // Moves the metadata to the front of the file, so it can be played while it is being downloaded
        writer.shouldOptimizeForNetworkUse = true

        let videoWidth = self.isLandscape ? Self.videoLongSide : Self.videoShortSide
        let videoHeight = self.isLandscape ? Self.videoShortSide : Self.videoLongSide

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264.rawValue,
            AVVideoWidthKey: videoWidth,
            AVVideoHeightKey: videoHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_500_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 60
            ] as [String: Any]
        ]

        let audioSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000
        ]

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true

        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else { return false }

        writer.add(videoInput)
        writer.add(audioInput)

        self.writer = writer
        self.writerVideoInput = videoInput
        self.writerAudioInput = audioInput
        self.sessionStartTime = nil
        self.isWriting = true

        return true
    }

    // MARK: - Sample buffers

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard self.isWriting, let writer = self.writer, CMSampleBufferDataIsReady(sampleBuffer) else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let isVideo = output === self.videoOutput

        if writer.status == .unknown {
            // The file starts with the first video frame, audio before it is dropped
            guard isVideo else { return }

            guard writer.startWriting() else {
                self.isWriting = false
                DispatchQueue.main.async { self.onFailure?() }
                return
            }

            writer.startSession(atSourceTime: timestamp)
            self.sessionStartTime = timestamp
        }

        guard writer.status == .writing, let sessionStartTime = self.sessionStartTime else {
            if writer.status == .failed {
                self.isWriting = false
                DispatchQueue.main.async { self.onFailure?() }
            }

            return
        }

        if isVideo {
            if let input = self.writerVideoInput, input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
            }
        } else if CMTimeCompare(timestamp, sessionStartTime) >= 0,
                  let input = self.writerAudioInput, input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }

    // MARK: - Notifications

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        if let reasonValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int,
           AVCaptureSession.InterruptionReason(rawValue: reasonValue) == .audioDeviceInUseByAnotherClient {
            self.audioSessionRestorer.audioDeviceTakenByAnotherClient = true
        }

        DispatchQueue.main.async { self.onFailure?() }
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        DispatchQueue.main.async { self.onFailure?() }
    }
}

/// Live preview of the camera while recording a video message, with a button to switch the camera
final class VideoMessagePreviewView: CameraPreviewView {

    var onSwitchCamera: (() -> Void)?

    private lazy var switchCameraButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "arrow.triangle.2.circlepath.camera"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        button.layer.cornerRadius = 18
        button.accessibilityLabel = NSLocalizedString("Switch camera", comment: "")
        button.addAction(UIAction { [weak self] _ in self?.onSwitchCamera?() }, for: .touchUpInside)

        return button
    }()

    init(session: AVCaptureSession, interfaceOrientation: UIInterfaceOrientation, showsSwitchCameraButton: Bool) {
        super.init(session: session, interfaceOrientation: interfaceOrientation)

        self.layer.cornerRadius = 16
        self.layer.cornerCurve = .continuous

        self.addSubview(self.switchCameraButton)
        self.switchCameraButton.isHidden = !showsSwitchCameraButton

        NSLayoutConstraint.activate([
            self.switchCameraButton.widthAnchor.constraint(equalToConstant: 36),
            self.switchCameraButton.heightAnchor.constraint(equalToConstant: 36),
            self.switchCameraButton.topAnchor.constraint(equalTo: self.topAnchor, constant: 8),
            self.switchCameraButton.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8)
        ])

        // Tapping the preview switches the camera as well, as the button can not be reached while the
        // finger is still holding the record button
        if showsSwitchCameraButton {
            self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(previewTapped)))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func previewTapped() {
        self.onSwitchCamera?()
    }
}
