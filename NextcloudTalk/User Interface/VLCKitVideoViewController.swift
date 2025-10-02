//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import UIKit
import MobileVLCKit

@objc protocol VLCKitVideoViewControllerDelegate {
    @objc func vlckitVideoViewControllerDismissed(_ controller: VLCKitVideoViewController)
}

@objcMembers class VLCKitVideoViewController: UIViewController, VLCMediaPlayerDelegate {

    public weak var delegate: VLCKitVideoViewControllerDelegate?

    public static let supportedFileExtensions = ["webm", "mkv"]

    @IBOutlet weak var videoViewContainer: NCZoomableView!
    @IBOutlet weak var buttonView: UIStackView!
    @IBOutlet weak var jumpBackButton: UIButton!
    @IBOutlet weak var playPauseButton: UIButton!
    @IBOutlet weak var jumpForwardButton: UIButton!
    @IBOutlet weak var shareButton: UIButton!
    @IBOutlet weak var closeButton: UIButton!
    @IBOutlet weak var currentTimeLabel: UILabel!
    @IBOutlet weak var totalTimeLabel: UILabel!
    @IBOutlet weak var positionSlider: UISlider!

    private static let jumpInterval: Int32 = 10

    private var mediaPlayer: VLCMediaPlayer?
    private var filePath: String
    private var setPosition: Bool = false
    private var timeObserver: NSKeyValueObservation?
    private var remainingTimeObserver: NSKeyValueObservation?
    private var sliderValueObserver: NSKeyValueObservation?
    private var idleTimer: Timer?
    private var pauseAfterPlay: Bool = false
    private var videoView = UIView()

    init(filePath: String) {
        self.filePath = filePath

        super.init(nibName: "VLCKitVideoViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        self.mediaPlayer = VLCMediaPlayer()
        self.mediaPlayer?.delegate = self

        self.timeObserver = self.mediaPlayer?.observe(\.time, changeHandler: { _, _ in
            self.updateInformation()
        })

        self.remainingTimeObserver = self.mediaPlayer?.observe(\.remainingTime, changeHandler: { _, _ in
            self.updateInformation()
        })

        self.sliderValueObserver = self.positionSlider?.observe(\.value, changeHandler: { _, _ in
            // Make sure the slider is filled to 100% at value 1 since we hid the thumb
            if self.positionSlider.value == 1 {
                self.positionSlider.maximumTrackTintColor = .systemBlue
            } else {
                self.positionSlider.maximumTrackTintColor = .none
            }
        })

        self.currentTimeLabel.text = "--:--"
        self.totalTimeLabel.text = "--:--"
        self.positionSlider.value = 0

        // Set close button icon as template
        self.closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
    }

    @objc private func dismissViewController() {
        self.dismiss(animated: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.buttonView.layer.cornerRadius = self.buttonView.frame.size.height / 2
        self.closeButton.layer.cornerRadius = self.closeButton.frame.size.height / 2
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Set the inital frame size when the view appeared
        self.videoView.frame = self.videoViewContainer.frame
        self.videoViewContainer.replaceContentView(self.videoView)
        self.mediaPlayer?.drawable = self.videoView

        // Allow toggle of controls
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
        self.view.isUserInteractionEnabled = true
        self.view.addGestureRecognizer(tapGesture)
        self.videoView.addGestureRecognizer(tapGesture)

        // Make sure our singel tap recognizer does not interfere with the double tap recognizer of NCZoomableView
        if let doubleTapGestureRecognizer = self.videoViewContainer.doubleTapGestureRecoginzer {
            tapGesture.require(toFail: doubleTapGestureRecognizer)
        }

        self.resetMedia(drawFirstFrame: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        self.timeObserver?.invalidate()
        self.remainingTimeObserver?.invalidate()
        self.sliderValueObserver?.invalidate()

        self.mediaPlayer?.stop()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        self.delegate?.vlckitVideoViewControllerDismissed(self)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        guard let mediaPlayer = self.mediaPlayer else { return }

        // Since there's no way to redraw the current frame in VLCKit, we hide the view
        // if the playback was stopped to not have a disorted view
        if !mediaPlayer.isPlaying, self.mediaReachedEnd() {
            self.videoViewContainer.isHidden = true
        }

        coordinator.animate(alongsideTransition: nil) { _ in
            self.videoView.frame = self.videoViewContainer.frame
            self.videoViewContainer.contentViewSize = self.videoViewContainer.frame.size
            self.videoViewContainer.resizeContentView()
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    private func updateInformation() {
        self.positionSlider.value = self.mediaPlayer?.position ?? 0

        if let remainingTime = self.mediaPlayer?.remainingTime, let currentTime = self.mediaPlayer?.time {
            self.currentTimeLabel.text = currentTime.stringValue
            self.totalTimeLabel.text = VLCTime(int: abs(currentTime.intValue) + abs(remainingTime.intValue)).stringValue
        } else {
            self.currentTimeLabel.text = "-:-"
            self.totalTimeLabel.text = "-:-"
        }

        if let mediaPlayer, mediaPlayer.isSeekable {
            jumpBackButton.isEnabled = true
            jumpForwardButton.isEnabled = true
        } else {
            jumpBackButton.isEnabled = false
            jumpForwardButton.isEnabled = false
        }
    }

    private func resetMedia(drawFirstFrame: Bool) {
        self.mediaPlayer?.media = VLCMedia(path: self.filePath)

        if drawFirstFrame {
            self.pauseAfterPlay = true
            self.mediaPlayer?.play()
        }
    }

    private func mediaReachedEnd() -> Bool {
        guard let mediaPlayer = self.mediaPlayer else { return false }

        return mediaPlayer.remainingTime?.stringValue == "00:00"
    }

    // MARK: Controls Visibility

    private func updateIdleTimer() {
        self.idleTimer?.invalidate()

        self.idleTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false, block: { _ in
            self.idleTimer = nil

            guard let mediaPlayer = self.mediaPlayer else { return }

            // Only hide the controls if we're playing something
            if mediaPlayer.isPlaying {
                self.hideControls()
            }
        })
    }

    @objc private func toggleControls() {
        if self.buttonView.alpha == 1 {
            self.setControlsAlpha(alpha: 0)
        } else {
            self.setControlsAlpha(alpha: 1)
            self.updateIdleTimer()
        }
    }

    private func showControls() {
        self.setControlsAlpha(alpha: 1)
    }

    private func hideControls() {
        self.setControlsAlpha(alpha: 0)
    }

    private func setControlsAlpha(alpha: CGFloat) {
        UIView.animate(withDuration: 0.3) {
            self.buttonView.alpha = alpha
            self.positionSlider.alpha = alpha
            self.totalTimeLabel.alpha = alpha
            self.currentTimeLabel.alpha = alpha
            self.closeButton.alpha = alpha
        }
    }

    // MARK: InterfaceBuilder Actions

    @IBAction func jumpBackButtonTap(_ sender: Any) {
        guard let mediaPlayer = self.mediaPlayer else { return }

        mediaPlayer.jumpBackward(Self.jumpInterval)
        updateInformation()
        updateIdleTimer()
    }

    @IBAction func jumpForwardButtonTap(_ sender: Any) {
        guard let mediaPlayer = self.mediaPlayer else { return }

        // VLCKit does not clamp to the media end, if the jump is beyond its length.
        // Hence the destination must be calculated manually to mimic first party video playback views.

        if let remainingTime = mediaPlayer.remainingTime {
            let remainingSeconds = abs(remainingTime.intValue) / 1000

            if remainingSeconds >= Self.jumpInterval {
                mediaPlayer.jumpForward(Self.jumpInterval)
            } else {
                mediaPlayer.jumpForward(remainingSeconds)
            }
        }

        updateInformation()
        updateIdleTimer()
    }

    @IBAction func playPauseButtonTap(_ sender: Any) {
        guard let mediaPlayer = self.mediaPlayer else { return }

        if mediaPlayer.isPlaying {
            mediaPlayer.pause()
        } else {
            // In VLCKit 3.3.17 the position parameter is not working correctly (fixed in 4.0.0)
            // see https://code.videolan.org/videolan/VLCKit/-/issues/583
            if self.mediaReachedEnd() {
                // When we reached the end of the media, start from the beginning again
                self.resetMedia(drawFirstFrame: false)
            }

            mediaPlayer.play()
        }

        self.updateIdleTimer()
    }

    @IBAction func shareButtonTap(_ sender: Any) {
        let activityItem = NSURL(fileURLWithPath: filePath)

        let activityVC = UIActivityViewController(activityItems: [activityItem], applicationActivities: nil)
        self.present(activityVC, animated: true, completion: nil)

        self.updateIdleTimer()
    }

    @IBAction func positionSliderAction(_ sender: Any) {
        // From the example of VLCKit we should limit the number of events to make sure,
        // the user actually sees I-frames when seeking
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let mediaPlayer = self.mediaPlayer else { return }

            if !self.setPosition {
                self.setPosition = false

                // When the media is in state "ended"/"stopped" we can't seek anymore, so we need to reset the media
                if self.mediaReachedEnd() {
                    self.resetMedia(drawFirstFrame: true)
                }

                mediaPlayer.position = self.positionSlider.value
                self.updateIdleTimer()
            }
        }
    }

    @IBAction func closeButtonTap(_ sender: Any) {
        self.dismissViewController()
    }

    // MARK: VLCMediaPlayerDelegate

    func mediaPlayerStateChanged(_ aNotification: Notification!) {
        guard let mediaPlayer = self.mediaPlayer else { return }

        if mediaPlayer.isPlaying {
            // When state changed to playing because we reseted the stream and
            // started playing to load it, we want to pause it here again, as it wasn't playing before
            if self.pauseAfterPlay {
                self.pauseAfterPlay = false
                mediaPlayer.pause()

                return
            }

            self.playPauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
            self.videoViewContainer.isHidden = false
        } else {
            self.playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
            self.showControls()

            // Check if we reached the end, although maybe not reported by the position (fixed in 4.0.0)
            if self.mediaReachedEnd() {
                self.positionSlider.value = 1
            }
        }
    }
}
