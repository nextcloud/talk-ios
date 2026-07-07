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

        contentView.frame = bounds

        contentView.backgroundColor = .systemBackground
        leftBackgroundView.backgroundColor = .systemBackground

        startTimeLabelTimer()

        recordingImageView.image = UIImage(systemName: "mic.fill")
        recordingImageView.tintColor = .systemRed
        recordingImageView.contentMode = .scaleAspectFit
        UIView.animate(withDuration: 0.5, delay: 0, options: [.repeat, .autoreverse]) {
            self.recordingImageView.alpha = 0
        }

        let swipeToCancelString = NSLocalizedString("Slide to cancel", comment: "")
        slideToCancelHintLabel.text = "<< \(swipeToCancelString)"
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
