//
// Copyright (c) 2024 Marcel Müller <marcel-mueller@gmx.de>
//
// Author Marcel Müller <marcel-mueller@gmx.de>
//
// GNU GPL version 3 or any later version
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

extension BaseChatTableViewCell {

    func setupForMessageCell(with message: NCChatMessage) {
        if self.messageTextView == nil {
            let messageTextView = MessageBodyTextView()
            self.messageTextView = messageTextView

            messageTextView.translatesAutoresizingMaskIntoConstraints = false

            self.messageBodyView.addSubview(messageTextView)

            NSLayoutConstraint.activate([
                messageTextView.leftAnchor.constraint(equalTo: self.messageBodyView.leftAnchor),
                messageTextView.rightAnchor.constraint(equalTo: self.messageBodyView.rightAnchor),
                messageTextView.topAnchor.constraint(equalTo: self.messageBodyView.topAnchor),
                messageTextView.bottomAnchor.constraint(equalTo: self.messageBodyView.bottomAnchor)
            ])
        }

        guard let messageTextView = self.messageTextView else { return }

        messageTextView.attributedText = message.parsedMarkdownForChat()
    }

    func prepareForReuseMessageCell() {
        self.messageTextView?.text = ""
    }
}
