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

        // Duration label
        hideDurationLabel()

        backgroundColor = .systemGray5
        layer.cornerRadius = 8.0
        layer.masksToBounds = true

        self.addSubview(contentView)
    }

    func setPlayerProgress(_ progress: CGFloat, isPlaying playing: Bool, maximumValue maxValue: CGFloat) {
        setPlayPauseButton(playing: playing)
        slider.isEnabled = true
        slider.value = Float(progress)
        slider.maximumValue = Float(maxValue)
        setDurationLabel(progress: progress, duration: maxValue)
        slider.setNeedsLayout()
    }

    func resetPlayer() {
        setPlayPauseButton(playing: false)
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
