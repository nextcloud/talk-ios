//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation
import Toast
import UIKit

/// What the record button next to an empty input field records
enum RecordButtonMode: String {
    case voice
    case video
}

/// Video messages: the record button records a short video instead of a voice message when it is in
/// video mode. The gestures are the ones of voice messages, see `handleLongPressInVoiceMessageRecordButton`.
extension BaseChatViewController {

    // MARK: - Availability

    var isVoiceMessageRecordingAvailable: Bool {
        return NCDatabaseManager.sharedInstance().roomHasTalkCapability(.voiceMessage, for: self.room) && !self.room.isFederated
    }

    /// Videos are sent as files, which is not possible in federated conversations (just like the attachment menu),
    /// and the camera is in use during a call.
    var isVideoMessageRecordingAvailable: Bool {
        return !self.room.isFederated
            && InAppCameraViewController.isCameraAvailable
            && NCRoomsManager.shared.callViewController == nil
    }

    /// The mode that is used for recording, as the chosen mode might not be available in this conversation
    var effectiveRecordMode: RecordButtonMode {
        switch (self.isVoiceMessageRecordingAvailable, self.isVideoMessageRecordingAvailable) {
        case (true, false):
            return .voice
        case (false, true):
            return .video
        default:
            return self.recordButtonMode
        }
    }

    /// With scheduled messages the button is a clock that opens them, so it can not switch the mode
    private var canSwitchRecordButtonMode: Bool {
        return self.isVoiceMessageRecordingAvailable && self.isVideoMessageRecordingAvailable && !self.room.hasScheduledMessages
    }

    // MARK: - Mode switch

    func handleTapOnRecordButton() {
        if self.canSwitchRecordButtonMode {
            self.recordButtonMode = self.effectiveRecordMode == .voice ? .video : .voice
            self.showVoiceMessageRecordButton()
        }

        self.showRecordButtonHint()
    }

    private func showRecordButtonHint() {
        let hint: String

        if self.canSwitchRecordButtonMode {
            if self.effectiveRecordMode == .video {
                hint = NSLocalizedString("Tap and hold to record a video. Tap to switch to voice messages.", comment: "")
            } else {
                hint = NSLocalizedString("Tap and hold to record a voice message. Tap to switch to video messages.", comment: "")
            }
        } else if self.effectiveRecordMode == .video {
            hint = NSLocalizedString("Tap and hold to record a video, release the button to send it.", comment: "")
        } else {
            self.showVoiceMessageRecordHint()
            return
        }

        let toastPosition = CGPoint(x: self.textInputbar.center.x, y: self.textInputbar.center.y - self.textInputbar.frame.size.height)
        self.view.makeToast(hint, duration: 3, point: toastPosition, title: nil, image: nil, completion: nil)
    }

    // MARK: - Gesture

    /// Starts recording in the current mode when the record button is pressed and held
    func startRecordingForGesture() {
        // The mode is fixed for the whole gesture
        self.isVideoGestureActive = self.effectiveRecordMode == .video

        if self.isVideoGestureActive {
            self.checkPermissionsAndRecordVideoMessage()
        } else {
            self.checkPermissionAndRecordVoiceMessage()
        }

        self.setInputbarImage(UIImage(systemName: self.isVideoGestureActive ? "video" : "mic"), for: self.rightButton)
    }

    /// Stops what `startRecordingForGesture` started. A voice message is handled by its recorder, which
    /// sends it when it is finished, so `send` only applies to videos.
    func stopRecordingForGesture(send: Bool) {
        if self.isVideoGestureActive {
            self.finishVideoMessageRecording(send: send)
        } else {
            self.stopRecordingVoiceMessage()
        }
    }

    // MARK: - Permissions

    func checkPermissionsAndRecordVideoMessage() {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        if cameraStatus == .authorized, microphoneStatus == .authorized {
            self.startRecordingVideoMessage()
            return
        }

        if cameraStatus == .denied || cameraStatus == .restricted {
            self.presentCaptureAccessDeniedAlert(title: NSLocalizedString("Could not access camera", comment: ""),
                                                 message: NSLocalizedString("Camera access is not allowed. Check your settings.", comment: ""))
            return
        }

        if microphoneStatus == .denied || microphoneStatus == .restricted {
            self.presentCaptureAccessDeniedAlert(title: NSLocalizedString("Could not access microphone", comment: ""),
                                                 message: NSLocalizedString("Microphone access is not allowed. Check your settings.", comment: ""))
            return
        }

        // Like for voice messages, the recording does not start while the system asks for the permission
        BaseChatViewController.requestCaptureAccessIfNeeded(for: .video) {
            BaseChatViewController.requestCaptureAccessIfNeeded(for: .audio) {}
        }
    }

    fileprivate static func requestCaptureAccessIfNeeded(for mediaType: AVMediaType, completion: @escaping () -> Void) {
        guard AVCaptureDevice.authorizationStatus(for: mediaType) == .notDetermined else {
            completion()
            return
        }

        AVCaptureDevice.requestAccess(for: mediaType) { granted in
            NSLog("Capture permission for %@ granted: %@", mediaType.rawValue, granted ? "YES" : "NO")
            completion()
        }
    }

    private func presentCaptureAccessDeniedAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        NCUserInterfaceController.sharedInstance().presentAlertViewController(alert)
    }

    // MARK: - Recording

    private func startRecordingVideoMessage() {
        // A recording that is still being stopped has its own recorder, so this only guards against a second start
        guard self.videoMessageRecorder == nil else { return }

        // Playing a voice message and recording do not go together
        self.pauseVoiceMessagePlayer()

        let recorder = VideoMessageRecorder(interfaceOrientation: CameraCaptureHelpers.interfaceOrientation(of: self.view))
        recorder.onFailure = { [weak self, weak recorder] in
            guard let self, let recorder, self.videoMessageRecorder === recorder else { return }

            NCLog.log("Video message recording failed or was interrupted")
            self.finishVideoMessageRecording(send: false)
            self.presentVideoMessageDiscardedHint()
        }

        self.videoMessageRecorder = recorder

        self.showVoiceMessageRecordingView(iconName: "video.fill")
        self.showVideoMessagePreview(for: recorder)

        recorder.start { [weak self, weak recorder] success in
            guard let self, let recorder, self.videoMessageRecorder === recorder else { return }

            guard success else {
                NCLog.log("Could not start recording a video message")
                self.finishVideoMessageRecording(send: false)
                self.presentVideoMessageDiscardedHint()
                return
            }

            // The recording stops and is sent when the maximum duration is reached
            let timer = Timer(timeInterval: VideoMessageRecorder.maxDuration, repeats: false) { [weak self] _ in
                self?.finishVideoMessageRecording(send: true)
            }

            RunLoop.main.add(timer, forMode: .common)
            self.videoMessageLimitTimer = timer
        }
    }

    /// Stops recording, and sends the video unless it is cancelled or shorter than a second
    func finishVideoMessageRecording(send: Bool) {
        guard let recorder = self.videoMessageRecorder else { return }

        self.videoMessageRecorder = nil
        self.videoMessageLimitTimer?.invalidate()
        self.videoMessageLimitTimer = nil

        let isLongEnough = recorder.elapsed >= 1

        self.hideVideoMessagePreview()

        self.hideVoiceMessageRecordingView()
        self.handleCollapseVoiceRecording()
        self.resetVoiceRecordingLockButton()
        self.shouldLockInterfaceOrientation(lock: false)

        // Brings back the icon of the mode, or the clock when there are scheduled messages
        self.showVoiceMessageRecordButton()

        recorder.stop(keepFile: send && isLongEnough) { [weak self] fileURL in
            guard let fileURL else { return }

            self?.shareVideoMessage(fileURL: fileURL)
        }
    }

    /// A recording that could not go on is dropped, which would otherwise be invisible
    private func presentVideoMessageDiscardedHint() {
        let toastPosition = CGPoint(x: self.textInputbar.center.x, y: self.textInputbar.center.y - self.textInputbar.frame.size.height)
        self.view.makeToast(NSLocalizedString("Video message could not be recorded", comment: ""), duration: 3, point: toastPosition, title: nil, image: nil, completion: nil)
    }

    private func showVideoMessagePreview(for recorder: VideoMessageRecorder) {
        // Dims the chat and keeps the touches away from it, the preview and the recording panel are the only things
        // to use while recording
        let scrimView = UIView()
        scrimView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        scrimView.isUserInteractionEnabled = true
        scrimView.isAccessibilityElement = false

        let previewView = VideoMessagePreviewView(session: recorder.session,
                                                  interfaceOrientation: CameraCaptureHelpers.interfaceOrientation(of: self.view),
                                                  showsSwitchCameraButton: recorder.canSwitchCamera)
        previewView.onSwitchCamera = { [weak recorder] in
            recorder?.switchCamera()
        }

        // The connection of the preview is created again with the camera, so the orientation is applied once more
        recorder.onCameraSwitched = { [weak self] in
            self?.videoMessagePreviewView?.setNeedsLayout()
            self?.updateVideoMessagePreviewLayout()
        }

        self.view.addSubview(scrimView)
        self.view.addSubview(previewView)
        self.videoMessageScrimView = scrimView
        self.videoMessagePreviewView = previewView

        // The gesture of the lock needs its button to be seen
        self.bringVoiceRecordingLockButtonToFront()

        // VoiceOver reads the recording panel and the switch camera button, not the chat behind them
        self.tableView?.accessibilityElementsHidden = true

        self.updateVideoMessagePreviewLayout()

        UIAccessibility.post(notification: .layoutChanged, argument: previewView)
    }

    /// Adds a view to the chat, below the dimming of a video recording when it is shown, so it is not left over it
    func addBelowVideoMessageScrim(_ overlayView: UIView) {
        if let scrimView = self.videoMessageScrimView {
            self.view.insertSubview(overlayView, belowSubview: scrimView)
        } else {
            self.view.addSubview(overlayView)
        }
    }

    /// Removes the preview and what is shown with it, whatever the way the recording ended
    private func hideVideoMessagePreview() {
        self.videoMessagePreviewView?.removeFromSuperview()
        self.videoMessagePreviewView = nil
        self.videoMessageScrimView?.removeFromSuperview()
        self.videoMessageScrimView = nil
        self.lockedVideoSendButton?.removeFromSuperview()
        self.lockedVideoSendButton = nil

        self.tableView?.accessibilityElementsHidden = false
        self.rightButton.accessibilityElementsHidden = false

        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }

    /// Places the preview in the free space above the recording panel: it follows the orientation of the interface,
    /// and is placed again whenever the layout changes, e.g. by a rotation.
    func updateVideoMessagePreviewLayout() {
        guard let previewView = self.videoMessagePreviewView else { return }

        let inputbarTop = self.view.convert(self.textInputbar.bounds, from: self.textInputbar).minY
        self.videoMessageScrimView?.frame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: max(inputbarTop, 0))

        let insets = self.view.safeAreaInsets
        let area = CGRect(x: insets.left,
                          y: insets.top,
                          width: self.view.bounds.width - insets.left - insets.right,
                          height: inputbarTop - insets.top)

        let orientation = CameraCaptureHelpers.interfaceOrientation(of: self.view)

        // Only what is shown follows the orientation. The file keeps the one the recording started in.
        previewView.interfaceOrientation = orientation
        previewView.frame = VideoMessagePreviewPlacement.frame(in: area, aspect: VideoMessagePreviewPlacement.frameAspect(for: orientation))
    }

    // MARK: - Sending

    /// Uploads the video like a voice message, without a confirmation, but as an ordinary file: it has no
    /// message type, so everyone sees a regular video.
    private func shareVideoMessage(fileURL: URL) {
        self.shareRecording(fromPath: fileURL.path, namePrefix: "Talk video from", fileExtension: "mp4", isVoiceMessage: false)
    }
}
