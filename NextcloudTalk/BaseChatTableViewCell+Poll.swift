//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

extension BaseChatTableViewCell {

    func setupForPollCell(with message: NCChatMessage) {
        if self.pollMessageView == nil {
            // Poll message view
            let pollMessageView = PollMessageView(frame: .zero)
            self.pollMessageView = pollMessageView

            pollMessageView.translatesAutoresizingMaskIntoConstraints = false

            pollMessageView.layer.cornerRadius = 8.0
            pollMessageView.layer.masksToBounds = true
            pollMessageView.layer.borderWidth = 1.0
            pollMessageView.layer.borderColor = NCAppBranding.placeholderColor().cgColor

            self.messageBodyView.addSubview(pollMessageView)

            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(pollViewTapped))
            pollMessageView.addGestureRecognizer(tapGesture)
            pollMessageView.isUserInteractionEnabled = true

            NSLayoutConstraint.activate([
                pollMessageView.leftAnchor.constraint(equalTo: self.messageBodyView.leftAnchor),
                pollMessageView.rightAnchor.constraint(equalTo: self.messageBodyView.rightAnchor),
                pollMessageView.topAnchor.constraint(equalTo: self.messageBodyView.topAnchor),
                pollMessageView.bottomAnchor.constraint(equalTo: self.messageBodyView.bottomAnchor)
            ])
        }

        guard let pollMessageView = self.pollMessageView else { return }

        pollMessageView.pollTitleTextView.text = message.parsedMessage().string
    }

    @objc func pollViewTapped() {
        guard let poll = message?.poll else {
            return
        }

        self.delegate?.cellWants(toOpenPoll: poll)
    }
}
