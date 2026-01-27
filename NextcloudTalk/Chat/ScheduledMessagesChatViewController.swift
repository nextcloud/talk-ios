//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class ScheduledMessagesChatViewController: BaseChatViewController {

    public override init?(forRoom room: NCRoom, withAccount account: TalkAccount) {
        super.init(forRoom: room, withAccount: account)

        // No need for an input bar when viewing scheduled messages
        self.textInputbar.isHidden = true

        // Scroll to bottom manually after hiding the textInputbar, otherwise the
        // scrollToBottom button might be briefly visible even if not needed
        self.tableView?.slk_scrollToBottom(animated: false)

        let closeButton = UIBarButtonItem(title: nil, style: .plain, target: nil, action: nil)
        closeButton.primaryAction = UIAction(title: NSLocalizedString("Close", comment: ""), handler: { [unowned self] _ in
            self.dismiss(animated: true)
        })
        self.navigationItem.rightBarButtonItems = [closeButton]

        Task {
            await self.showScheduledMessages()
        }
    }

    @MainActor required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setTitleView() {
        super.setTitleView()

        self.titleView?.updateForScheduledMessages(in: self.room)
    }

    public func showScheduledMessages() async {
        do {
            let scheduledMessages = try await NCAPIController.sharedInstance().getScheduledMessages(forRoom: self.room.token, forAccount: self.account)
            self.appendMessages(messages: scheduledMessages.compactMap { $0.asChatMessage() })
            self.tableView?.reloadData()
            self.tableView?.slk_scrollToBottom(animated: false)
        } catch {

        }

        self.chatBackgroundView.loadingView.stopAnimating()
        self.chatBackgroundView.loadingView.isHidden = true
    }

    // MARK: - Editing support

    public override func didCommitTextEditing(_ sender: Any) {
        guard let editingMessage else { return }

        let messageParametersJSONString = self.mentionsDict.asJSONString() ?? ""
        editingMessage.message = self.replaceMentionsDisplayNamesWithMentionsKeysInMessage(message: self.textView.text, parameters: messageParametersJSONString)
        editingMessage.messageParametersJSONString = messageParametersJSONString

        Task {
            do {
                let updatedMessage = try await NCAPIController.sharedInstance().editScheduledMessage(String(editingMessage.messageId), withMessage: editingMessage.sendingMessage, inRoom: self.room.token, sendAt: editingMessage.timestamp, forAccount: self.account)
                self.updateMessage(withMessageId: editingMessage.messageId, updatedMessage: updatedMessage.asChatMessage())
                super.didCommitTextEditing(sender)
                self.setTextInputbarHidden(true, animated: true)

                NotificationPresenter.shared().present(text: NSLocalizedString("Message successfully edited", comment: ""), dismissAfterDelay: 5.0, includedStyle: .success)
            } catch {
                print(error)
                NotificationPresenter.shared().present(text: NSLocalizedString("Message editing failed", comment: ""), dismissAfterDelay: 5.0, includedStyle: .error)
            }
        }
    }

    public override func didCancelTextEditing(_ sender: Any) {
        super.didCancelTextEditing(sender)
        self.setTextInputbarHidden(true, animated: true)
    }

    // MARK: - Action methods

    func didPressReschedule(for message: NCChatMessage, at indexPath: IndexPath) async {
        let startingDate = Date(timeIntervalSince1970: TimeInterval(message.timestamp))
        let minimumDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())

        self.datePickerTextField.setupDatePicker(startingDate: startingDate, minimumDate: minimumDate)

        let (buttonTapped, selectedDate) = await self.datePickerTextField.getDate()
        guard buttonTapped == .done, let selectedDate else { return }

        do {
            let timestamp = Int(selectedDate.timeIntervalSince1970)
            let updatedMessage = try await NCAPIController.sharedInstance().editScheduledMessage(String(message.messageId), withMessage: message.sendingMessage, inRoom: self.room.token, sendAt: timestamp, forAccount: self.account)

            // TODO: Update message does not support moving to a different section, therefore we remove and insert the updated message
            self.removeMessage(at: indexPath)
            self.insertMessages(messages: [updatedMessage.asChatMessage()])
            self.tableView?.reloadData()

            NotificationPresenter.shared().present(text: NSLocalizedString("Message successfully rescheduled", comment: ""), dismissAfterDelay: 5.0, includedStyle: .success)
        } catch {
            print(error)
            NotificationPresenter.shared().present(text: NSLocalizedString("Message rescheduling failed", comment: ""), dismissAfterDelay: 5.0, includedStyle: .error)
        }
    }

    func didPressSendNow(for message: NCChatMessage, at indexPath: IndexPath) {
        // "Duplicate" code, since sendChatMessage is not available in BaseChatViewController,
        // but we can't just move the code to ChatViewController as we then need a second ChatController instance
        var replyTo = message.parent

        // On thread view, include original thread message as parent message (if there is not parent)
        if let thread = self.thread, replyTo == nil {
            replyTo = thread.firstMessage()
        }

        guard
            let temporaryMessage = self.createTemporaryMessage(message: message.message, replyTo: replyTo, messageParameters: message.messageParametersJSONString ?? "", silently: message.isSilent, isVoiceMessage: false),
            let chatController = NCChatController(for: self.room)
        else { return }

        // Send message
        chatController.send(temporaryMessage)

        Task {
            await self.didPressDeleteScheduled(for: message, at: indexPath)
        }

        self.dismiss(animated: true)
        NCRoomsManager.shared.updateRoom(self.room.token)
    }

    func didPressDeleteScheduled(for message: NCChatMessage, at indexPath: IndexPath) async {
        do {
            try await NCAPIController.sharedInstance().deleteScheduledMessage(String(message.messageId), inRoom: self.room.token, forAccount: self.account)
        } catch {
            NotificationPresenter.shared().present(text: NSLocalizedString("An error occurred while deleting the message", comment: ""), dismissAfterDelay: 5.0, includedStyle: .error)
            return
        }

        self.removeMessage(at: indexPath)

        if self.messages.values.isEmpty {
            self.dismiss(animated: true)
            NCRoomsManager.shared.updateRoom(self.room.token)
        }
    }

    // MARK: - TableView overrides

    public override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let message = self.message(for: indexPath) else { return nil }

        var actions: [UIMenuElement] = []

        // Copy option
        actions.append(UIAction(title: NSLocalizedString("Copy", comment: ""), image: .init(systemName: "doc.on.doc")) { _ in
            self.didPressCopy(for: message)
        })

        // Copy Selection
        actions.append(UIAction(title: NSLocalizedString("Copy message selection", comment: ""), image: .init(systemName: "text.viewfinder")) { _ in
            self.didPressCopySelection(for: message)
        })

        // Reschedule option
        actions.append(UIAction(title: NSLocalizedString("Reschedule", comment: "Reschedule a message that is send later"), image: .init(systemName: "calendar.badge.clock")) { _ in
            Task {
                await self.didPressReschedule(for: message, at: indexPath)
            }
        })

        // Send now option
        actions.append(UIAction(title: NSLocalizedString("Send now", comment: "Send a message now"), image: .init(systemName: "paperplane")) { _ in
            self.didPressSendNow(for: message, at: indexPath)
        })

        var destructiveMenuActions: [UIMenuElement] = []

        // Edit option
        destructiveMenuActions.append(UIAction(title: NSLocalizedString("Edit", comment: "Edit a message or room participants"), image: .init(systemName: "pencil")) { _ in
            self.setTextInputbarHidden(false, animated: true)
            self.textView.layer.cornerRadius = self.textView.frame.size.height / 2
            self.didPressEdit(for: message)
        })

        // Delete option
        destructiveMenuActions.append(UIAction(title: NSLocalizedString("Delete", comment: ""), image: .init(systemName: "trash"), attributes: .destructive) { _ in
            Task {
                await self.didPressDeleteScheduled(for: message, at: indexPath)
            }
        })

        if !destructiveMenuActions.isEmpty {
            actions.append(UIMenu(options: [.displayInline], children: destructiveMenuActions))
        }

        let menu = UIMenu(children: actions)

        let configuration = UIContextMenuConfiguration(identifier: indexPath as NSIndexPath) {
            return nil
        } actionProvider: { _ in
            return menu
        }

        return configuration
    }
}
