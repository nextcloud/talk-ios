//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

protocol AudioPlayerViewDelegate: AnyObject {

    func audioPlayerPlayButtonPressed()
    func audioPlayerPauseButtonPressed()
    func audioPlayerProgressChanged(progress: CGFloat)
}

class AudioPlayerView: UIView {

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var playPauseButton: UIButton!
    @IBOutlet weak var slider: UISlider!
    @IBOutlet weak var durationLabel: UILabel!

    var isPlaying: Bool = false

    // Only shown while this player's audio file is loaded
    private let speedButton = UIButton(type: .system)
    private var speedButtonWidthConstraint: NSLayoutConstraint?

    public weak var delegate: AudioPlayerViewDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    override var intrinsicContentSize: CGSize {
        return bounds.size
    }

    func commonInit() {
        Bundle.main.loadNibNamed("AudioPlayerView", owner: self, options: nil)

        contentView.frame = self.bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Play/Pause button
        playPauseButton.addAction(for: .touchUpInside) { [unowned self] in
            if isPlaying {
                delegate?.audioPlayerPauseButtonPressed()
            } else {
                delegate?.audioPlayerPlayButtonPressed()
            }
        }

        // Slider
        let thumbImage = UIImage(systemName: "circle.fill")?
                    .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16))
                    .withTintColor(.label, renderingMode: .alwaysOriginal)
        slider.setThumbImage(thumbImage, for: .normal)
        slider.semanticContentAttribute = .forceLeftToRight
        slider.addAction(for: .valueChanged) { [unowned self] in
            delegate?.audioPlayerProgressChanged(progress: CGFloat(slider.value))
        }

        // Playback speed
        self.setupSpeedButton()

        // Duration label
        hideDurationLabel()

        backgroundColor = .systemGray5
        layer.cornerRadius = 8.0
        layer.masksToBounds = true

        self.addSubview(contentView)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupSpeedButton() {
        speedButton.translatesAutoresizingMaskIntoConstraints = false
        speedButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        speedButton.setTitleColor(.label, for: .normal)
        speedButton.backgroundColor = .systemGray4
        speedButton.layer.cornerRadius = 10
        speedButton.layer.masksToBounds = true
        speedButton.accessibilityLabel = NSLocalizedString("Playback speed", comment: "")
        speedButton.addAction(for: .touchUpInside) {
            VoiceMessagePlaybackSpeed.current = VoiceMessagePlaybackSpeed.next(after: VoiceMessagePlaybackSpeed.current)
        }

        contentView.addSubview(speedButton)

        // Place the button between the slider and the duration label
        if let sliderToLabel = contentView.constraints.first(where: {
            ($0.firstItem === durationLabel && $0.secondItem === slider) || ($0.firstItem === slider && $0.secondItem === durationLabel)
        }) {
            sliderToLabel.isActive = false
        }

        let widthConstraint = speedButton.widthAnchor.constraint(equalToConstant: 0)
        speedButtonWidthConstraint = widthConstraint

        NSLayoutConstraint.activate([
            widthConstraint,
            speedButton.heightAnchor.constraint(equalToConstant: 22),
            speedButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            speedButton.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 8),
            durationLabel.leadingAnchor.constraint(equalTo: speedButton.trailingAnchor, constant: 8)
        ])

        setSpeedButtonVisible(false)

        NotificationCenter.default.addObserver(self, selector: #selector(playbackSpeedDidChange), name: VoiceMessagePlaybackSpeed.didChangeNotification, object: nil)
    }

    @objc private func playbackSpeedDidChange() {
        self.updateSpeedButtonTitle()
    }

    private func updateSpeedButtonTitle() {
        let speed = VoiceMessagePlaybackSpeed.current
        speedButton.setTitle(VoiceMessagePlaybackSpeed.label(for: speed), for: .normal)
        speedButton.accessibilityValue = VoiceMessagePlaybackSpeed.label(for: speed)
    }

    private func setSpeedButtonVisible(_ visible: Bool) {
        if visible {
            updateSpeedButtonTitle()
        }

        speedButton.isHidden = !visible
        speedButtonWidthConstraint?.constant = visible ? 38 : 0
    }

    func setPlayerProgress(_ progress: CGFloat, isPlaying playing: Bool, maximumValue maxValue: CGFloat) {
        setPlayPauseButton(playing: playing)
        setSpeedButtonVisible(true)
        slider.isEnabled = true
        slider.value = Float(progress)
        slider.maximumValue = Float(maxValue)
        setDurationLabel(progress: progress, duration: maxValue)
        slider.setNeedsLayout()
    }

    func resetPlayer() {
        setPlayPauseButton(playing: false)
        setSpeedButtonVisible(false)
        slider.isEnabled = false
        slider.value = 0
        hideDurationLabel()
        slider.setNeedsLayout()
    }

    func setPlayPauseButton(playing: Bool) {
        isPlaying = playing

        if isPlaying {
            playPauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        } else {
            playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        }
    }

    func setDurationLabel(progress: CGFloat, duration: CGFloat) {
        let dateComponentsFormatter = DateComponentsFormatter()
        dateComponentsFormatter.allowedUnits = [.minute, .second]
        dateComponentsFormatter.zeroFormattingBehavior = []

        let progressTime = dateComponentsFormatter.string(from: TimeInterval(progress)) ?? "0:00"
        let durationTime = dateComponentsFormatter.string(from: TimeInterval(duration)) ?? "0:00"

        let playerTimeString = "\(progressTime)".withTextColor(.label).withFont(.systemFont(ofSize: 13, weight: .medium))
        playerTimeString.append(" / \(durationTime)".withTextColor(.secondaryLabel).withFont(.systemFont(ofSize: 13)))

        durationLabel.attributedText = playerTimeString
    }

    func hideDurationLabel() {
        durationLabel.text = ""
    }
}
