//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation
import Toast
import UIKit

@MainActor
protocol InAppCameraViewControllerDelegate: AnyObject {
    /// A photo (.jpg or .heic) or a video (.mov) was captured. The file is in the temporary directory and belongs to the delegate.
    func inAppCameraViewController(_ controller: InAppCameraViewController, didCaptureMediaAt fileURL: URL)

    /// The camera was closed without capturing anything
    func inAppCameraViewControllerDidCancel(_ controller: InAppCameraViewController)
}

/// Full screen camera: a tap on the shutter button takes a photo, holding it records a video with sound.
/// The microphone is only asked for and used when the first video is recorded.
/// The camera does not close itself, that is up to the delegate.
final class InAppCameraViewController: UIViewController {

    weak var delegate: InAppCameraViewControllerDelegate?

    /// Whether the device has a camera
    static var isCameraAvailable: Bool {
        return AVCaptureDevice.default(for: .video) != nil
    }

    // How long the shutter button needs to be held to record a video instead of taking a photo
    private static let holdDuration: TimeInterval = 0.35

    private let captureSession = InAppCameraCaptureSession()

    private var flashMode = InAppCameraFlashMode(storedValue: NCUserDefaults.preferredCameraFlashMode())

    // State of the shutter button
    private var holdWorkItem: DispatchWorkItem?
    private var isRecordingRequested = false
    private var isCapturingPhoto = false
    private var discardsRecording = false
    private var recordingStartDate: Date?
    private var recordingTimer: Timer?

    private var isSessionRunning = false
    private var isSessionStarted = false
    private var isCaptureAvailable = false
    private var isShown = false
    private var isClosing = false

    // The layout of the buttons follows the body of the device, see `updateBodyLayout`
    private var bodyConstraints: [NSLayoutConstraint] = []
    private var layoutOrientation: UIInterfaceOrientation?

    // The angle the icons are rotated to, it is not limited to a circle so the animation takes the short way
    private var iconAngle: Double = 0

    // The last orientation the device was held in, for when it lies flat. Interface is portrait on the phone, so
    // the interface can not tell how the device is held.
    private var lastHeldOrientation: UIDeviceOrientation = .unknown

    // Set while the interface rotates, the icons are turned when it is done
    private var isInterfaceTransitioning = false
    private var iconRotationWorkItem: DispatchWorkItem?

    // MARK: - Views

    private lazy var previewView: CameraPreviewView = CameraPreviewView(session: self.captureSession.session, interfaceOrientation: .portrait)

    private lazy var closeButton: UIButton = self.makeCircleButton(symbolName: "xmark", accessibilityLabel: NSLocalizedString("Close", comment: "")) { [weak self] in
        self?.closeTapped()
    }

    private lazy var flashButton: UIButton = self.makeCircleButton(symbolName: self.flashMode.symbolName, accessibilityLabel: self.flashMode.accessibilityLabel) { [weak self] in
        self?.flashTapped()
    }

    private lazy var switchCameraButton: UIButton = self.makeCircleButton(symbolName: "arrow.triangle.2.circlepath.camera", accessibilityLabel: NSLocalizedString("Switch camera", comment: "")) { [weak self] in
        self?.switchCameraTapped()
    }

    private let shutterView = InAppCameraShutterView()

    private lazy var timerLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor.systemRed
        label.layer.cornerRadius = 12
        label.layer.masksToBounds = true
        label.isHidden = true
        label.text = InAppCameraSupport.formattedDuration(0)

        return label
    }()

    private lazy var hintLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = NSLocalizedString("Tap for photo, hold for video", comment: "")

        return label
    }()

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0

        return label
    }()

    private lazy var settingsButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(NSLocalizedString("Settings", comment: ""), for: .normal)
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        button.addAction(UIAction { _ in
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        }, for: .touchUpInside)

        return button
    }()

    private lazy var statusStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [self.statusLabel, self.settingsButton])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 12
        stackView.isHidden = true

        return stackView
    }()

    private lazy var flashOverlayView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .white
        view.alpha = 0
        view.isUserInteractionEnabled = false

        return view
    }()

    // MARK: - Lifecycle

    init() {
        super.init(nibName: nil, bundle: nil)

        self.modalPresentationStyle = .fullScreen
        self.overrideUserInterfaceStyle = .dark
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .black

        self.setupViews()
        self.setupCaptureCallbacks()
        self.updateFlashButton()
        self.updateControls()

        self.updateBodyLayout()

        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(deviceOrientationDidChange), name: UIDevice.orientationDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.isShown = true

        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        self.updatePreviewOrientation()
        self.updateBodyLayout()
        self.updateIconRotation(animated: false)
        self.evaluateAvailability()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        self.isShown = false

        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        self.holdWorkItem?.cancel()
        self.holdWorkItem = nil
        self.stopSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.updatePreviewOrientation()
        self.updateBodyLayout()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        self.isInterfaceTransitioning = true

        // The orientation of the interface is the new one at the latest when the transition is done
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.isInterfaceTransitioning = false
            self?.updatePreviewOrientation()
            self?.updateBodyLayout()
            self?.updateIconRotation(animated: false)
        }
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    /// The interface stays in portrait on the phone, only the icons turn with the device. The iPad has to rotate for
    /// multitasking, there the buttons are laid out along the body of the device instead.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return UIDevice.current.userInterfaceIdiom == .pad ? super.preferredInterfaceOrientationForPresentation : .portrait
    }

    // MARK: - Setup

    private func setupViews() {
        self.previewView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.previewView)
        self.view.addSubview(self.flashOverlayView)
        self.view.addSubview(self.statusStackView)
        self.view.addSubview(self.hintLabel)
        self.view.addSubview(self.shutterView)
        self.view.addSubview(self.closeButton)
        self.view.addSubview(self.flashButton)
        self.view.addSubview(self.switchCameraButton)
        self.view.addSubview(self.timerLabel)

        self.shutterView.translatesAutoresizingMaskIntoConstraints = false
        self.shutterView.accessibilityLabel = NSLocalizedString("Take photo", comment: "")
        self.shutterView.accessibilityHint = NSLocalizedString("Tap for photo, hold for video", comment: "")
        self.shutterView.onAccessibilityActivate = { [weak self] in
            guard let self else { return }

            if self.isRecordingRequested {
                self.stopRecording()
            } else {
                self.takePhoto()
            }
        }

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(shutterGestureChanged))
        // A press is a photo or a video depending on its length, no matter how the finger moves
        longPress.minimumPressDuration = 0
        longPress.allowableMovement = .greatestFiniteMagnitude
        self.shutterView.addGestureRecognizer(longPress)

        // Like in the apps of the platform, a double tap on the picture switches the camera
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(previewDoubleTapped))
        doubleTap.numberOfTapsRequired = 2
        self.previewView.addGestureRecognizer(doubleTap)

        let safeArea = self.view.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            self.previewView.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.previewView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.previewView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.previewView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),

            self.flashOverlayView.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.flashOverlayView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.flashOverlayView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.flashOverlayView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),

            // The place of the timer, the buttons and the hint is set in updateBodyLayout
            self.timerLabel.heightAnchor.constraint(equalToConstant: 24),
            self.timerLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),

            self.shutterView.widthAnchor.constraint(equalToConstant: InAppCameraShutterView.size),
            self.shutterView.heightAnchor.constraint(equalToConstant: InAppCameraShutterView.size),

            self.hintLabel.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 16),
            self.hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -16),

            self.statusStackView.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            self.statusStackView.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
            self.statusStackView.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 32),
            self.statusStackView.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -32)
        ])
    }

    // MARK: - Layout along the body of the device

    /// Lays out the buttons along the body of the device: the shutter at the natural bottom (the edge with the
    /// home button), the switch of the camera next to it, close and flash at the natural top. On the phone the interface
    /// is always in portrait, so this is the normal layout there. On the iPad the interface rotates, so the
    /// edges of the body are moved to the edges of the screen they are at.
    private func updateBodyLayout() {
        let orientation = CameraCaptureHelpers.interfaceOrientation(of: self.view)

        guard orientation != self.layoutOrientation else { return }

        self.layoutOrientation = orientation

        let bodyEdge = { (edge: InAppCameraEdge) in InAppCameraSupport.screenEdge(ofBodyEdge: edge, interface: orientation) }
        let shutterEdge = bodyEdge(.bottom)
        let topEdge = bodyEdge(.top)
        let sideOfSwitch = bodyEdge(.right).outwardDirection
        let towardsTop = topEdge.outwardDirection

        // The center of the switch is the radius of the shutter, the space and the radius of the switch away
        let switchDistance = InAppCameraShutterView.size / 2 + 40 + 22

        var constraints = [
            self.pinConstraint(self.shutterView, to: shutterEdge, inset: 24),
            self.centerAlongConstraint(self.shutterView, edge: shutterEdge),

            self.switchCameraButton.centerXAnchor.constraint(equalTo: self.shutterView.centerXAnchor, constant: CGFloat(sideOfSwitch.dx) * switchDistance),
            self.switchCameraButton.centerYAnchor.constraint(equalTo: self.shutterView.centerYAnchor, constant: CGFloat(sideOfSwitch.dy) * switchDistance),

            self.pinConstraint(self.closeButton, to: topEdge, inset: 12),
            self.pinConstraint(self.closeButton, to: bodyEdge(.left), inset: 16),
            self.pinConstraint(self.flashButton, to: topEdge, inset: 12),
            self.pinConstraint(self.flashButton, to: bodyEdge(.right), inset: 16),

            // The timer is on the line of the centers of the buttons, at any edge
            self.centerAlongConstraint(self.timerLabel, edge: topEdge),
            self.centerAcrossConstraint(self.timerLabel, edge: topEdge, like: self.closeButton),

            self.centerAlongConstraint(self.hintLabel, edge: shutterEdge)
        ]

        // The hint is on the side of the shutter that points to the top of the body
        if towardsTop.dy < 0 {
            constraints.append(self.hintLabel.bottomAnchor.constraint(equalTo: self.shutterView.topAnchor, constant: -16))
        } else if towardsTop.dy > 0 {
            constraints.append(self.hintLabel.topAnchor.constraint(equalTo: self.shutterView.bottomAnchor, constant: 16))
        } else if towardsTop.dx > 0 {
            constraints.append(self.hintLabel.leftAnchor.constraint(equalTo: self.shutterView.rightAnchor, constant: 16))
        } else {
            constraints.append(self.hintLabel.rightAnchor.constraint(equalTo: self.shutterView.leftAnchor, constant: -16))
        }

        NSLayoutConstraint.deactivate(self.bodyConstraints)
        NSLayoutConstraint.activate(constraints)
        self.bodyConstraints = constraints

        self.updateIconRotation(animated: false)
    }

    /// Fixes a view at a distance from an edge of the safe area. Left and right are the sides of the screen, they do
    /// not turn around in a language that is written from the right, as the body of the device does not either.
    private func pinConstraint(_ view: UIView, to edge: InAppCameraEdge, inset: CGFloat) -> NSLayoutConstraint {
        let safeArea = self.view.safeAreaLayoutGuide

        switch edge {
        case .top: return view.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: inset)
        case .bottom: return view.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -inset)
        case .left: return view.leftAnchor.constraint(equalTo: safeArea.leftAnchor, constant: inset)
        case .right: return view.rightAnchor.constraint(equalTo: safeArea.rightAnchor, constant: -inset)
        }
    }

    /// Puts a view in the middle of the screen along an edge
    private func centerAlongConstraint(_ view: UIView, edge: InAppCameraEdge) -> NSLayoutConstraint {
        switch edge {
        case .top, .bottom: return view.centerXAnchor.constraint(equalTo: self.view.centerXAnchor)
        case .left, .right: return view.centerYAnchor.constraint(equalTo: self.view.centerYAnchor)
        }
    }

    /// Puts a view on the line of the center of another one, across the direction of an edge
    private func centerAcrossConstraint(_ view: UIView, edge: InAppCameraEdge, like other: UIView) -> NSLayoutConstraint {
        switch edge {
        case .top, .bottom: return view.centerYAnchor.constraint(equalTo: other.centerYAnchor)
        case .left, .right: return view.centerXAnchor.constraint(equalTo: other.centerXAnchor)
        }
    }

    // MARK: - Rotation of the icons

    @objc private func deviceOrientationDidChange() {
        self.iconRotationWorkItem?.cancel()
        self.iconRotationWorkItem = nil

        guard UIDevice.current.userInterfaceIdiom == .pad else {
            self.updateIconRotation(animated: true)
            return
        }

        // On the iPad the interface rotates too, and the notification can come before the interface has its new
        // orientation. The angle is calculated a moment later, so it is the one against the new interface. When the
        // rotation is locked the interface does not change, and the icons turn after the same moment.
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isInterfaceTransitioning else { return }

            self.updateIconRotation(animated: true)
        }

        self.iconRotationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    /// The orientation the device is held in. When it lies flat, or is not known, it is the last one it was held in.
    private func heldOrientation() -> UIDeviceOrientation {
        self.lastHeldOrientation = InAppCameraSupport.heldOrientation(current: UIDevice.current.orientation, last: self.lastHeldOrientation)

        return self.lastHeldOrientation
    }

    /// Turns the icons so they are upright for the person who holds the device. Flat or unknown keeps the angle.
    private func updateIconRotation(animated: Bool) {
        guard let degrees = InAppCameraSupport.iconRotationDegrees(device: self.heldOrientation(),
                                                                   interface: CameraCaptureHelpers.interfaceOrientation(of: self.view)) else { return }

        let target = InAppCameraSupport.shortestRotationTarget(current: self.iconAngle, target: degrees)

        guard target != self.iconAngle else { return }

        self.iconAngle = target

        let transform = CGAffineTransform(rotationAngle: CGFloat(target * .pi / 180))
        let rotate = {
            for view in [self.closeButton, self.flashButton, self.switchCameraButton] {
                view.transform = transform
            }
        }

        if animated {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: rotate)
        } else {
            rotate()
        }
    }

    private func makeCircleButton(symbolName: String, accessibilityLabel: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        button.layer.cornerRadius = 22
        button.accessibilityLabel = accessibilityLabel
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44)
        ])

        return button
    }

    private func setupCaptureCallbacks() {
        self.captureSession.onConfigurationChanged = { [weak self] in
            self?.updateFlashButton()
            self?.updateControls()

            // The connection of the preview is new after the session started or the camera was switched
            self?.previewView.setNeedsLayout()
        }

        self.captureSession.onInterruptionChanged = { [weak self] isInterrupted in
            guard let self, self.isShown else { return }

            if isInterrupted {
                self.showStatus(NSLocalizedString("The camera is not available right now", comment: ""), showsSettings: false)
            } else {
                self.showStatus(nil)
            }
        }

        self.captureSession.onRuntimeError = { [weak self] in
            NCLog.log("Runtime error of the session of the in-app camera")
            self?.updateControls()
        }

        self.captureSession.onPhotoCaptured = { [weak self] result in
            self?.photoCaptured(result)
        }

        self.captureSession.onRecordingStarted = { [weak self] in
            self?.recordingStarted()
        }

        self.captureSession.onRecordingFinished = { [weak self] result in
            self?.recordingFinished(result)
        }
    }

    // MARK: - Availability

    /// Starts the camera when it can be used. It can not be used when it is denied, or during a call, as the call needs it.
    private func evaluateAvailability() {
        guard self.isShown else { return }

        if NCRoomsManager.shared.callViewController != nil {
            self.stopSession()
            self.showStatus(NSLocalizedString("The camera can not be used during a call", comment: ""), showsSettings: false)
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                Task { @MainActor in
                    self?.evaluateAvailability()
                }
            }
        default:
            self.stopSession()
            self.showStatus(NSLocalizedString("Camera access is not allowed. Check your settings.", comment: ""), showsSettings: true)
        }
    }

    private func startSession() {
        guard !self.isSessionRunning else { return }

        self.isSessionRunning = true
        self.showStatus(nil)

        self.captureSession.start { [weak self] success in
            guard let self, self.isSessionRunning else { return }

            if success {
                // The shutter works as soon as the session runs
                self.isSessionStarted = true
                self.showStatus(nil)
            } else {
                NCLog.log("Could not start the in-app camera")
                self.isSessionRunning = false
                self.showStatus(NSLocalizedString("The camera is not available right now", comment: ""), showsSettings: false)
            }
        }
    }

    private func stopSession() {
        guard self.isSessionRunning else { return }

        self.isSessionRunning = false
        self.isSessionStarted = false
        self.finishRecordingForTeardown()
        self.captureSession.stop()
        self.updateControls()
    }

    /// Shows a message over the picture, or nothing when the camera can be used
    private func showStatus(_ message: String?, showsSettings: Bool = false) {
        self.statusLabel.text = message
        self.settingsButton.isHidden = !showsSettings
        self.statusStackView.isHidden = message == nil

        self.isCaptureAvailable = message == nil && self.isSessionStarted
        self.updateControls()
    }

    @objc private func applicationDidBecomeActive() {
        self.evaluateAvailability()
    }

    @objc private func applicationWillResignActive() {
        // The recording ends in the background anyway, so the video that exists until now is kept
        if self.isRecordingRequested {
            self.stopRecording()
        }
    }

    // MARK: - Controls

    private func updateControls() {
        let canSwitch = self.captureSession.canSwitchCamera && self.isCaptureAvailable && !self.isRecordingRequested

        self.switchCameraButton.isHidden = !canSwitch
        self.shutterView.alpha = self.isCaptureAvailable ? 1 : 0.4
        self.shutterView.isUserInteractionEnabled = self.isCaptureAvailable
        self.hintLabel.isHidden = self.isRecordingRequested || !self.isCaptureAvailable
        self.flashButton.isHidden = !self.captureSession.supportsFlash || !self.isCaptureAvailable
        self.updateShutterAccessibility()
    }

    /// The shutter only takes photos with VoiceOver, so recording a video is an action of its own
    private func updateShutterAccessibility() {
        let title = self.isRecordingRequested ? NSLocalizedString("Stop recording", comment: "") : NSLocalizedString("Record video", comment: "Accessibility action of the shutter button of the camera that starts recording a video")

        self.shutterView.accessibilityCustomActions = self.isCaptureAvailable || self.isRecordingRequested ? [
            UIAccessibilityCustomAction(name: title) { [weak self] _ in
                guard let self else { return false }

                if self.isRecordingRequested {
                    self.stopRecording()
                } else {
                    self.startRecording()
                }

                return true
            }
        ] : nil
    }

    private func updateFlashButton() {
        self.flashButton.setImage(UIImage(systemName: self.flashMode.symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)), for: .normal)
        self.flashButton.accessibilityLabel = self.flashMode.accessibilityLabel
        self.updateControls()
    }

    private func updatePreviewOrientation() {
        self.previewView.interfaceOrientation = CameraCaptureHelpers.interfaceOrientation(of: self.view)
    }

    /// The orientation a photo or a video is captured in
    private var captureOrientation: UIInterfaceOrientation {
        return InAppCameraSupport.captureOrientation(device: self.heldOrientation(),
                                                     interface: CameraCaptureHelpers.interfaceOrientation(of: self.view))
    }

    // MARK: - Actions

    private func closeTapped() {
        self.isClosing = true
        self.holdWorkItem?.cancel()

        if self.isRecordingRequested {
            // What is recorded so far is dropped
            self.discardsRecording = true
            self.stopRecording()
        }

        self.delegate?.inAppCameraViewControllerDidCancel(self)
    }

    private func flashTapped() {
        self.flashMode = self.flashMode.next
        NCUserDefaults.setPreferredCameraFlashMode(self.flashMode.rawValue)
        self.updateFlashButton()
    }

    private func switchCameraTapped() {
        guard !self.isRecordingRequested else { return }

        self.captureSession.switchCamera()
    }

    @objc private func previewDoubleTapped() {
        self.switchCameraTapped()
    }

    // MARK: - Shutter

    @objc private func shutterGestureChanged(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            self.shutterPressed()
        case .ended:
            self.shutterReleased(cancelled: false)
        case .cancelled, .failed:
            self.shutterReleased(cancelled: true)
        default:
            break
        }
    }

    private func shutterPressed() {
        guard self.isCaptureAvailable, !self.isCapturingPhoto, !self.isRecordingRequested else { return }

        self.shutterView.setPressed(true)

        let workItem = DispatchWorkItem { [weak self] in
            self?.startRecording()
        }

        self.holdWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDuration, execute: workItem)
    }

    private func shutterReleased(cancelled: Bool) {
        let wasWaitingForHold = self.holdWorkItem != nil

        self.holdWorkItem?.cancel()
        self.holdWorkItem = nil

        if self.isRecordingRequested {
            self.stopRecording()
        } else {
            self.shutterView.setPressed(false)

            // Released before the time of a video: a photo
            if wasWaitingForHold, !cancelled {
                self.takePhoto()
            }
        }
    }

    // MARK: - Photo

    private func takePhoto() {
        guard self.isCaptureAvailable, !self.isCapturingPhoto, !self.isRecordingRequested else { return }

        self.isCapturingPhoto = true
        self.captureSession.capturePhoto(flashMode: self.flashMode, orientation: self.captureOrientation)

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        self.flashOverlayView.alpha = 0.8
        UIView.animate(withDuration: 0.25) {
            self.flashOverlayView.alpha = 0
        }
    }

    private func photoCaptured(_ result: Result<URL, Error>) {
        self.isCapturingPhoto = false

        switch result {
        case .success(let url):
            // A closed camera has no use for the photo, like for a video
            if self.isClosing || !self.isShown {
                try? FileManager.default.removeItem(at: url)
            } else {
                self.deliver(url)
            }
        case .failure(let error):
            NCLog.log("Could not take a photo with the in-app camera: \(error.localizedDescription)")
            self.showMessage(NSLocalizedString("Could not take the photo", comment: ""))
        }
    }

    // MARK: - Video

    private func startRecording() {
        self.holdWorkItem = nil

        guard self.isCaptureAvailable, !self.isCapturingPhoto, !self.isRecordingRequested else { return }

        // The access to the microphone is asked for with the first video. The finger is on the shutter
        // while the question is shown, so the video is recorded with the next hold.
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            self.shutterView.setPressed(false)

            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            return
        }

        self.isRecordingRequested = true
        self.discardsRecording = false
        self.updateControls()

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        self.captureSession.startRecording(flashMode: self.flashMode, orientation: self.captureOrientation)
    }

    private func stopRecording() {
        self.captureSession.stopRecording()
    }

    private func recordingStarted() {
        self.recordingStartDate = Date()

        self.timerLabel.text = InAppCameraSupport.formattedDuration(0)
        self.timerLabel.isHidden = false
        self.shutterView.setRecording(true)

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateRecordingTimer()
        }

        RunLoop.main.add(timer, forMode: .common)
        self.recordingTimer = timer
    }

    private func updateRecordingTimer() {
        guard let startDate = self.recordingStartDate else { return }

        self.timerLabel.text = InAppCameraSupport.formattedDuration(Date().timeIntervalSince(startDate))
    }

    private func recordingFinished(_ result: Result<URL, Error>) {
        self.recordingTimer?.invalidate()
        self.recordingTimer = nil
        self.recordingStartDate = nil
        self.isRecordingRequested = false

        self.timerLabel.isHidden = true
        self.shutterView.setRecording(false)
        self.shutterView.setPressed(false)
        self.updateControls()

        let discards = self.discardsRecording
        self.discardsRecording = false

        switch result {
        case .success(let url):
            // A closed camera has no use for the video
            if discards || self.isClosing || !self.isShown {
                try? FileManager.default.removeItem(at: url)
            } else {
                self.deliver(url)
            }
        case .failure(let error):
            NCLog.log("Could not record a video with the in-app camera: \(error.localizedDescription)")

            if !discards {
                self.showMessage(NSLocalizedString("Could not record the video", comment: ""))
            }
        }
    }

    /// The camera goes away, so what is recorded is dropped
    private func finishRecordingForTeardown() {
        self.holdWorkItem?.cancel()
        self.holdWorkItem = nil

        if self.isRecordingRequested {
            self.discardsRecording = true
            self.stopRecording()
        }
    }

    // MARK: - Result

    private func deliver(_ url: URL) {
        guard let delegate = self.delegate else {
            try? FileManager.default.removeItem(at: url)
            return
        }

        delegate.inAppCameraViewController(self, didCaptureMediaAt: url)
    }

    private func showMessage(_ message: String) {
        let position = CGPoint(x: self.view.bounds.midX, y: self.view.bounds.height * 0.3)
        self.view.makeToast(message, duration: 3, point: position, title: nil, image: nil, completion: nil)
    }
}

/// The big round button of the camera. The ring stays, the inner circle shrinks and turns red while recording.
private final class InAppCameraShutterView: UIView {

    static let size: CGFloat = 76

    /// Called when the button is activated with VoiceOver or another assistive technology
    var onAccessibilityActivate: (() -> Void)?

    private let ringView = UIView()
    private let innerView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.isAccessibilityElement = true
        self.accessibilityTraits = .button

        let innerSize = Self.size - 14

        self.ringView.translatesAutoresizingMaskIntoConstraints = false
        self.ringView.layer.borderColor = UIColor.white.cgColor
        self.ringView.layer.borderWidth = 4
        self.ringView.layer.cornerRadius = Self.size / 2
        self.ringView.isUserInteractionEnabled = false

        self.innerView.translatesAutoresizingMaskIntoConstraints = false
        self.innerView.backgroundColor = .white
        self.innerView.layer.cornerRadius = innerSize / 2
        self.innerView.isUserInteractionEnabled = false

        self.addSubview(self.ringView)
        self.addSubview(self.innerView)

        NSLayoutConstraint.activate([
            self.ringView.topAnchor.constraint(equalTo: self.topAnchor),
            self.ringView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.ringView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.ringView.trailingAnchor.constraint(equalTo: self.trailingAnchor),

            self.innerView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.innerView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.innerView.widthAnchor.constraint(equalToConstant: innerSize),
            self.innerView.heightAnchor.constraint(equalToConstant: innerSize)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func accessibilityActivate() -> Bool {
        self.onAccessibilityActivate?()
        return true
    }

    func setPressed(_ pressed: Bool) {
        UIView.animate(withDuration: 0.15) {
            self.innerView.transform = pressed ? CGAffineTransform(scaleX: 0.88, y: 0.88) : .identity
        }
    }

    func setRecording(_ recording: Bool) {
        UIView.animate(withDuration: 0.2) {
            self.innerView.backgroundColor = recording ? .systemRed : .white
            self.innerView.transform = recording ? CGAffineTransform(scaleX: 0.6, y: 0.6) : .identity
            self.transform = recording ? CGAffineTransform(scaleX: 1.15, y: 1.15) : .identity
        }
    }
}
