//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

extension BaseChatTableViewCell {

    func setupForFileGroupCell(with group: FileMessageGroup, with account: TalkAccount) {
        if self.groupedFilePreviewView == nil {
            let groupedFilePreviewView = GroupedFilePreviewView()
            self.groupedFilePreviewView = groupedFilePreviewView

            groupedFilePreviewView.translatesAutoresizingMaskIntoConstraints = false
            groupedFilePreviewView.delegate = self
            groupedFilePreviewView.accessibilityIdentifier = "groupedFilePreviewView"

            self.messageBodyView.addSubview(groupedFilePreviewView)

            let messageTextView = MessageBodyTextView()
            self.messageTextView = messageTextView

            messageTextView.translatesAutoresizingMaskIntoConstraints = false

            self.messageBodyView.addSubview(messageTextView)

            // Without a caption the text view is taken out of the layout entirely. Hiding it is not
            // enough: an empty text view still takes its line height, which would make the body
            // taller than the cell was measured to be, and everything below it stops taking taps.
            self.fileGroupCaptionConstraints = [
                messageTextView.topAnchor.constraint(equalTo: groupedFilePreviewView.bottomAnchor, constant: 10),
                messageTextView.bottomAnchor.constraint(equalTo: self.messageBodyView.bottomAnchor)
            ]

            self.fileGroupWithoutCaptionConstraint = groupedFilePreviewView.bottomAnchor.constraint(equalTo: self.messageBodyView.bottomAnchor)

            NSLayoutConstraint.activate([
                groupedFilePreviewView.leftAnchor.constraint(equalTo: self.messageBodyView.leftAnchor),
                groupedFilePreviewView.topAnchor.constraint(equalTo: self.messageBodyView.topAnchor),
                groupedFilePreviewView.rightAnchor.constraint(lessThanOrEqualTo: self.messageBodyView.rightAnchor),
                messageTextView.leftAnchor.constraint(equalTo: self.messageBodyView.leftAnchor),
                messageTextView.rightAnchor.constraint(equalTo: self.messageBodyView.rightAnchor)
            ])
        }

        guard let groupedFilePreviewView = self.groupedFilePreviewView,
              let messageTextView = self.messageTextView
        else { return }

        groupedFilePreviewView.setup(with: group, account: account, availableWidth: self.availableBodyWidth)

        // The caption is carried by the file shared last, which is what the group is shown as
        let hasCaption = !group.anchor.sharesFileWithoutCaption

        messageTextView.isHidden = !hasCaption
        messageTextView.attributedText = hasCaption ? group.anchor.parsedMarkdownForChat() : nil
        messageTextView.dataDetectorTypes = hasCaption ? .all : []

        self.fileGroupWithoutCaptionConstraint?.isActive = false
        NSLayoutConstraint.deactivate(self.fileGroupCaptionConstraints)

        if hasCaption {
            NSLayoutConstraint.activate(self.fileGroupCaptionConstraints)
        } else {
            self.fileGroupWithoutCaptionConstraint?.isActive = true
        }
    }

    func prepareForReuseFileGroupCell() {
        self.groupedFilePreviewView?.prepareForReuse()
    }
}

extension BaseChatTableViewCell: GroupedFilePreviewViewDelegate {

    func groupedFilePreviewView(_ view: GroupedFilePreviewView, didSelectFileAt index: Int) {
        guard let messages = self.fileGroup?.messagesInUploadOrder, index < messages.count else { return }

        let message = messages[index]

        guard let file = message.file(), file.path != nil else { return }

        self.delegate?.cellWants(toDownloadFile: file, for: message)
    }
}
