//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class ContextChatViewController: BaseChatViewController {

    override func setTitleView() {
        super.setTitleView()

        if thread != nil {
            self.titleView?.update(for: thread)
        }

        self.titleView?.longPressGestureRecognizer.isEnabled = false
    }

    public func showContext(ofMessageId messageId: Int, withLimit limit: Int, withCloseButton closeButton: Bool) {
        // Fetch the context of the message and update the BaseChatViewController
        let threadId = thread?.threadId ?? 0
        NCChatController(forThreadId: threadId, in: self.room).getMessageContext(forMessageId: messageId, withLimit: limit) { [weak self] messages in
            guard let self else { return }

            guard let messages, !messages.isEmpty else {
                let errorMessage = NSLocalizedString("Unable to get context of the message", comment: "")
                NotificationPresenter.shared().present(text: errorMessage, dismissAfterDelay: 5.0, includedStyle: .dark)
                return
            }

            self.appendMessages(messages: messages)
            self.reloadDataAndHighlightMessage(messageId: messageId)
        }

        if closeButton {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Close", comment: ""), primaryAction: UIAction { [unowned self] _ in
                self.dismiss(animated: true)
            })
        }
    }
}
