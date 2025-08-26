diff --git a/NextcloudTalk/AudioPlayerView.swift b/NextcloudTalk/AudioPlayerView.swift
index 37a0b6324f453ba652d41488dc8d335cdbfbfc14..d5d1d769794e19531ec8ff9c2c395b8437071c69 100644
--- a/NextcloudTalk/AudioPlayerView.swift
+++ b/NextcloudTalk/AudioPlayerView.swift
@@ -1,115 +1,137 @@
 //
 // SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
 // SPDX-License-Identifier: GPL-3.0-or-later
 //
 
 import UIKit
 
 protocol AudioPlayerViewDelegate: AnyObject {
 
     func audioPlayerPlayButtonPressed()
     func audioPlayerPauseButtonPressed()
     func audioPlayerProgressChanged(progress: CGFloat)
+    func audioPlayerSpeedChanged(to speed: Float)
 }
 
 class AudioPlayerView: UIView {
 
     @IBOutlet var contentView: UIView!
     @IBOutlet weak var playPauseButton: UIButton!
     @IBOutlet weak var slider: UISlider!
     @IBOutlet weak var durationLabel: UILabel!
+    @IBOutlet weak var speedButton: UIButton!
 
     var isPlaying: Bool = false
+    private let speedRates: [Float] = [1.0, 1.5, 2.0]
+    private var currentSpeedIndex = 0
 
     public weak var delegate: AudioPlayerViewDelegate?
 
     override init(frame: CGRect) {
         super.init(frame: frame)
         commonInit()
     }
 
     required init?(coder aDecoder: NSCoder) {
         super.init(coder: aDecoder)
         commonInit()
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
 
+        // Speed button
+        speedButton.setTitleColor(.label, for: .normal)
+        setPlaybackRate(to: speedRates[currentSpeedIndex])
+        speedButton.addAction(for: .touchUpInside) { [unowned self] in
+            currentSpeedIndex = (currentSpeedIndex + 1) % speedRates.count
+            let rate = speedRates[currentSpeedIndex]
+            setPlaybackRate(to: rate)
+            delegate?.audioPlayerSpeedChanged(to: rate)
+        }
+
         // Duration label
         hideDurationLabel()
 
         backgroundColor = .secondarySystemBackground
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
+        setPlaybackRate(to: speedRates[currentSpeedIndex])
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
+
+    func setPlaybackRate(to rate: Float) {
+        if let index = speedRates.firstIndex(of: rate) {
+            currentSpeedIndex = index
+        }
+        speedButton.setTitle("\(rate)x", for: .normal)
+    }
 }
