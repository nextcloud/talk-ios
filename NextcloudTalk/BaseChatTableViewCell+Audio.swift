//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

extension BaseChatTableViewCell {

    func setupForAudioCell(with message: NCChatMessage) {
        if self.audioPlayerView == nil {
            // Audio player view
            let audioPlayerView = AudioPlayerView(frame: CGRect(x: 0, y: 0, width: voiceMessageCellPlayerWidth, height: voiceMessageCellPlayerHeight))
            self.audioPlayerView = audioPlayerView
            self.audioPlayerView?.delegate = self

            audioPlayerView.translatesAutoresizingMaskIntoConstraints = false

            self.messageBodyView.addSubview(audioPlayerView)

            NSLayoutConstraint.activate([
                audioPlayerView.leftAnchor.constraint(equalTo: self.messageBodyView.leftAnchor),
                audioPlayerView.topAnchor.constraint(equalTo: self.messageBodyView.topAnchor),
                audioPlayerView.rightAnchor.constraint(lessThanOrEqualTo: self.messageBodyView.rightAnchor)
            ])
        }
    }

    func prepareForReuseAudioCell() {
        self.audioPlayerView?.resetPlayer()
        self.clearFileStatusView()
    }

    func audioPlayerPlayButtonPressed() {
        guard let audioFile = message else {
            return
        }

        self.delegate?.cellWants(toPlayAudioFile: audioFile)
    }

    func audioPlayerPauseButtonPressed() {
        guard let audioFileParameter = message?.file() else {
            return
        }

        self.delegate?.cellWants(toPauseAudioFile: audioFileParameter)
    }

    func audioPlayerProgressChanged(progress: CGFloat) {
        guard let audioFileParameter = message?.file() else {
            return
        }

        self.delegate?.cellWants(toChangeProgress: progress, fromAudioFile: audioFileParameter)
    }
}
