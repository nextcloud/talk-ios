//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation
import SwiftUI

// A short check before joining a call: a camera preview, a microphone level meter and the audio output,
// with the option to join with camera or microphone turned off.

struct CallPreflightResult: Equatable {
    let cameraEnabled: Bool
    let microphoneEnabled: Bool
}

// Hands the choice from the check over to the call view controller, which is created later through CallKit
enum CallPreflightPreferences {

    private struct PendingResult {
        let token: String
        let result: CallPreflightResult
        let date: Date
    }

    private static var pending: PendingResult?

    static func store(_ result: CallPreflightResult, for token: String) {
        pending = PendingResult(token: token, result: result, date: Date())
    }

    /// Returns the stored choice for the conversation once, if it was made in the last minute
    static func take(for token: String) -> CallPreflightResult? {
        guard let pending, pending.token == token, Date().timeIntervalSince(pending.date) < 60 else { return nil }

        self.pending = nil
        return pending.result
    }
}

class CallPreflightViewController: UIHostingController<CallPreflightView> {

    init(room: NCRoom, withVideo video: Bool, completion: @escaping (CallPreflightResult?) -> Void) {
        let model = CallPreflightModel(cameraAvailable: video && room.canPublishVideo,
                                       microphoneAvailable: room.permissions.contains(.canPublishAudio))

        var dismissHandler: ((CallPreflightResult?) -> Void)?
        let view = CallPreflightView(model: model, roomName: room.displayName) { result in
            dismissHandler?(result)
        }

        super.init(rootView: view)

        dismissHandler = { [weak self] result in
            model.stop()
            self?.dismiss(animated: true) {
                completion(result)
            }
        }

        self.modalPresentationStyle = .formSheet
        self.sheetPresentationController?.detents = [.large()]
        self.sheetPresentationController?.prefersGrabberVisible = true
        // Swiping the sheet away is the same as cancelling
        self.presentationController?.delegate = self
        self.cancelHandler = {
            model.stop()
            completion(nil)
        }
    }

    private var cancelHandler: (() -> Void)?

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func isNeeded(for room: NCRoom, withVideo video: Bool) -> Bool {
        guard NCUserDefaults.showCallPreflight() else { return false }

        return (video && room.canPublishVideo) || room.permissions.contains(.canPublishAudio)
    }
}

extension CallPreflightViewController: UIAdaptivePresentationControllerDelegate {

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        self.cancelHandler?()
    }
}

// MARK: - Model

@MainActor
class CallPreflightModel: ObservableObject {

    let cameraAvailable: Bool
    let microphoneAvailable: Bool

    @Published var cameraEnabled: Bool {
        didSet { self.updateCamera() }
    }

    @Published var microphoneEnabled: Bool {
        didSet { self.updateMicrophone() }
    }

    @Published var cameraState: DeviceState = .starting
    @Published var microphoneState: DeviceState = .starting
    // 0...1
    @Published var microphoneLevel: Float = 0
    @Published var audioOutputName = ""

    enum DeviceState {
        case starting, running, denied, unavailable
    }

    let captureSession = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "com.nextcloud.Talk.CallPreflight")
    private var cameraConfigured = false
    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var stopped = false

    init(cameraAvailable: Bool, microphoneAvailable: Bool) {
        self.cameraAvailable = cameraAvailable
        self.microphoneAvailable = microphoneAvailable
        self.cameraEnabled = cameraAvailable
        self.microphoneEnabled = microphoneAvailable
    }

    func start() {
        self.updateCamera()
        self.updateMicrophone()
    }

    func stop() {
        guard !stopped else { return }

        stopped = true
        self.stopMicrophone()

        let session = captureSession
        captureQueue.async {
            session.stopRunning()
        }
    }

    // MARK: Camera

    private func updateCamera() {
        guard cameraAvailable, !stopped else { return }

        guard cameraEnabled else {
            let session = captureSession
            captureQueue.async {
                session.stopRunning()
            }
            return
        }

        Task {
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                self.cameraState = .denied
                return
            }

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  let input = try? AVCaptureDeviceInput(device: device)
            else {
                self.cameraState = .unavailable
                return
            }

            let session = captureSession
            let needsConfiguration = !cameraConfigured
            cameraConfigured = true

            captureQueue.async {
                if needsConfiguration {
                    session.beginConfiguration()
                    session.sessionPreset = .medium

                    if session.canAddInput(input) {
                        session.addInput(input)
                    }

                    session.commitConfiguration()
                }

                session.startRunning()
            }

            self.cameraState = .running
        }
    }

    // MARK: Microphone

    private func updateMicrophone() {
        guard microphoneAvailable, !stopped else { return }

        guard microphoneEnabled else {
            self.stopMicrophone()
            return
        }

        Task {
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                self.microphoneState = .denied
                return
            }

            self.startMicrophone()
        }
    }

    private func startMicrophone() {
        guard recorder == nil, !stopped, microphoneEnabled else { return }

        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(.playAndRecord, mode: .videoChat, options: [.allowBluetoothHFP, .defaultToSpeaker])
            try audioSession.setActive(true)

            // The recording is only used for the level meter and deleted right away
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("call-preflight.m4a")
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 12000,
                AVNumberOfChannelsKey: 1
            ])

            recorder.isMeteringEnabled = true
            recorder.record()
            self.recorder = recorder
            self.microphoneState = .running
        } catch {
            NCLog.log("Could not start microphone check: \(error.localizedDescription)")
            self.microphoneState = .unavailable
            return
        }

        self.updateAudioOutputName()

        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else { return }

                recorder.updateMeters()
                self.microphoneLevel = CallPreflightModel.normalizedLevel(fromDecibels: recorder.averagePower(forChannel: 0))
            }
        }
    }

    private func stopMicrophone() {
        meterTimer?.invalidate()
        meterTimer = nil
        microphoneLevel = 0

        guard let recorder else { return }

        recorder.stop()
        recorder.deleteRecording()
        self.recorder = nil

        // Let CallKit take over the audio session again
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func updateAudioOutputName() {
        let output = AVAudioSession.sharedInstance().currentRoute.outputs.first
        self.audioOutputName = output?.portName ?? ""
    }

    /// Maps the average power in decibels (-160...0) to 0...1, where everything below -50 dB counts as silence
    nonisolated static func normalizedLevel(fromDecibels decibels: Float) -> Float {
        guard decibels.isFinite else { return 0 }

        return min(1, max(0, (decibels + 50) / 50))
    }
}

// MARK: - Views

struct CallPreflightView: View {

    @ObservedObject var model: CallPreflightModel
    let roomName: String
    let onFinish: (CallPreflightResult?) -> Void

    @State private var showBeforeEveryCall = NCUserDefaults.showCallPreflight()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text(NSLocalizedString("Ready to join?", comment: "Title of the check before joining a call"))
                        .font(.title2.bold())
                    Text(roomName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.top, 24)

                if model.cameraAvailable {
                    CameraPreview(model: model)
                        .frame(maxWidth: 360)
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                HStack(spacing: 24) {
                    if model.microphoneAvailable {
                        PreflightToggleButton(isOn: $model.microphoneEnabled,
                                              onImage: "mic.fill", offImage: "mic.slash.fill",
                                              label: NSLocalizedString("Microphone", comment: ""))
                    }

                    if model.cameraAvailable {
                        PreflightToggleButton(isOn: $model.cameraEnabled,
                                              onImage: "video.fill", offImage: "video.slash.fill",
                                              label: NSLocalizedString("Camera", comment: ""))
                    }
                }

                if model.microphoneAvailable {
                    MicrophoneCheck(model: model)
                }

                if !model.audioOutputName.isEmpty {
                    Label(model.audioOutputName, systemImage: "speaker.wave.2.fill")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Toggle(NSLocalizedString("Show this check before every call", comment: ""), isOn: $showBeforeEveryCall)
                    .font(.footnote)
                    .padding(.horizontal)
                    .onChange(of: showBeforeEveryCall) { newValue in
                        NCUserDefaults.setShowCallPreflight(newValue)
                    }

                VStack(spacing: 12) {
                    Button {
                        HapticFeedback.light()
                        onFinish(CallPreflightResult(cameraEnabled: model.cameraAvailable && model.cameraEnabled,
                                                     microphoneEnabled: model.microphoneAvailable && model.microphoneEnabled))
                    } label: {
                        Text(NSLocalizedString("Join call", comment: ""))
                            .bold()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(NCAppBranding.elementColor()))
                    .controlSize(.large)

                    Button(NSLocalizedString("Cancel", comment: "")) {
                        onFinish(nil)
                    }
                }
                .padding(.horizontal)
            }
            .padding()
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            model.start()
        }
    }
}

private struct PreflightToggleButton: View {

    @Binding var isOn: Bool
    let onImage: String
    let offImage: String
    let label: String

    var body: some View {
        Button {
            HapticFeedback.selection()
            isOn.toggle()
        } label: {
            Image(systemName: isOn ? onImage : offImage)
                .font(.title2)
                .foregroundColor(isOn ? .primary : .white)
                .frame(width: 60, height: 60)
                .background(Circle().fill(isOn ? Color(UIColor.secondarySystemFill) : Color.red))
        }
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? NSLocalizedString("On", comment: "") : NSLocalizedString("Off", comment: ""))
    }
}

private struct MicrophoneCheck: View {

    @ObservedObject var model: CallPreflightModel

    private let barCount = 16

    var body: some View {
        VStack(spacing: 8) {
            switch model.microphoneState {
            case .denied:
                Text(NSLocalizedString("Microphone access is not allowed", comment: ""))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            case .unavailable:
                Text(NSLocalizedString("No microphone available", comment: ""))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            default:
                HStack(spacing: 3) {
                    ForEach(0..<barCount, id: \.self) { index in
                        Capsule()
                            .fill(isLit(index) ? Color.green : Color(UIColor.systemGray4))
                            .frame(width: 6, height: 18)
                    }
                }
                .animation(.easeOut(duration: 0.08), value: model.microphoneLevel)
                .accessibilityHidden(true)

                Text(model.microphoneEnabled ?
                     NSLocalizedString("Say something to test your microphone", comment: "") :
                     NSLocalizedString("You will join muted", comment: "Shown before joining a call with the microphone turned off"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func isLit(_ index: Int) -> Bool {
        return model.microphoneEnabled && Float(index) < model.microphoneLevel * Float(barCount)
    }
}

private struct CameraPreview: View {

    @ObservedObject var model: CallPreflightModel

    var body: some View {
        ZStack {
            Color(UIColor.secondarySystemBackground)

            if model.cameraEnabled, model.cameraState == .running {
                CaptureVideoPreview(session: model.captureSession)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash.fill")
                        .font(.largeTitle)
                    Text(placeholderText)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
                .foregroundColor(.secondary)
                .padding()
            }
        }
    }

    private var placeholderText: String {
        switch model.cameraState {
        case .denied:
            return NSLocalizedString("Camera access is not allowed", comment: "")
        case .unavailable:
            return NSLocalizedString("No camera available", comment: "")
        default:
            return NSLocalizedString("You will join with the camera turned off", comment: "")
        }
    }
}

private struct CaptureVideoPreview: UIViewRepresentable {

    let session: AVCaptureSession

    class PreviewView: UIView {
        override class var layerClass: AnyClass {
            return AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            return layer as! AVCaptureVideoPreviewLayer
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
