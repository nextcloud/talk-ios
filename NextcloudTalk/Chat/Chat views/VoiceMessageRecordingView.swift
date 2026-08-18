//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

class VoiceMessageRecordingView: UIView {

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var leftBackgroundView: UIView!
    @IBOutlet weak var recordingImageView: UIImageView!
    @IBOutlet weak var slideToCancelHintLabel: UILabel!
    @IBOutlet weak var recordingTimeLabel: UILabel!

    private weak var labelTimer: Timer?
    private var startTimestamp = 0

    /// Clips the hint while it slides to the left, so it disappears behind the recording time
    private lazy var hintContainerView: UIView = {
        let hintContainerView = UIView()
        hintContainerView.translatesAutoresizingMaskIntoConstraints = false
        hintContainerView.backgroundColor = .clear
        hintContainerView.clipsToBounds = true

        return hintContainerView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        Bundle.main.loadNibNamed("VoiceMessageRecordingView", owner: self, options: nil)

        addSubview(contentView)

        contentView.backgroundColor = .systemBackground

        setupLayout()
        startTimeLabelTimer()

        recordingImageView.image = UIImage(systemName: "mic.fill")
        recordingImageView.tintColor = .systemRed
        recordingImageView.contentMode = .scaleAspectFit

        let swipeToCancelString = NSLocalizedString("Slide to cancel", comment: "")
        slideToCancelHintLabel.text = "<< \(swipeToCancelString)"
    }

    /// Pulses the microphone with a layer animation. A UIView animation would set the alpha of the view itself
    /// to zero, leaving the microphone invisible whenever the animation is removed.
    private func startPulseAnimation() {
        let pulseAnimation = CABasicAnimation(keyPath: "opacity")
        pulseAnimation.fromValue = 1
        pulseAnimation.toValue = 0
        pulseAnimation.duration = 0.5
        pulseAnimation.autoreverses = true
        pulseAnimation.repeatCount = .infinity

        recordingImageView.layer.add(pulseAnimation, forKey: "pulse")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        // Animations are removed while a layer is outside of the render tree
        if window != nil, recordingImageView.layer.animation(forKey: "pulse") == nil {
            startPulseAnimation()
        }
    }

    /// The xib places its subviews with fixed frames, made for an inputbar of a fixed height. Lay them out
    /// instead, so they fit whatever size this view is given.
    private func setupLayout() {
        // The xib does not use auto layout: its frames would win over the constraints below
        contentView.translatesAutoresizingMaskIntoConstraints = false
        recordingImageView.translatesAutoresizingMaskIntoConstraints = false
        recordingTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        slideToCancelHintLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(hintContainerView)
        hintContainerView.addSubview(slideToCancelHintLabel)

        // The hint is the only one to truncate when there is not enough room
        slideToCancelHintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),

            recordingImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            recordingImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            recordingImageView.widthAnchor.constraint(equalToConstant: 26),
            recordingImageView.heightAnchor.constraint(equalToConstant: 26),

            recordingTimeLabel.leadingAnchor.constraint(equalTo: recordingImageView.trailingAnchor, constant: 8),
            recordingTimeLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            hintContainerView.leadingAnchor.constraint(greaterThanOrEqualTo: recordingTimeLabel.trailingAnchor, constant: 8),
            hintContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            hintContainerView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            slideToCancelHintLabel.leadingAnchor.constraint(equalTo: hintContainerView.leadingAnchor),
            slideToCancelHintLabel.trailingAnchor.constraint(equalTo: hintContainerView.trailingAnchor),
            slideToCancelHintLabel.topAnchor.constraint(equalTo: hintContainerView.topAnchor),
            slideToCancelHintLabel.bottomAnchor.constraint(equalTo: hintContainerView.bottomAnchor)
        ])

        // The hint is clipped by its container now, so it doesn't need to slide behind an opaque view anymore
        leftBackgroundView.isHidden = true
    }

    /// Gives the recording view a glass capsule of its own, so it can take the place of the input field
    @available(iOS 26.0, *)
    public func useGlassBackground(cornerRadius: CGFloat) {
        contentView.backgroundColor = .clear

        let backgroundView = UIVisualEffectView(effect: UIGlassEffect())
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.isUserInteractionEnabled = false
        backgroundView.clipsToBounds = true
        backgroundView.layer.cornerCurve = .continuous
        backgroundView.layer.cornerRadius = cornerRadius

        contentView.insertSubview(backgroundView, at: 0)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func startTimeLabelTimer() {
        recordingTimeLabel.text = "00:00"
        startTimestamp = Int(Date().timeIntervalSince1970)
        labelTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.updateTimeLabel()
        }
    }

    public func stopTimeLabelTimer() {
        labelTimer?.invalidate()
    }

    public func getTimeCounted() -> Int {
        return Int(Date().timeIntervalSince1970) - startTimestamp
    }

    private func updateTimeLabel() {
        let duration = getTimeCounted()

        let minutes = duration / 60
        let seconds = duration % 60

        recordingTimeLabel.text = String(format: "%02ld:%02ld", minutes, seconds)
    }
}
