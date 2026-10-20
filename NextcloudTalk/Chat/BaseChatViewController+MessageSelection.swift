//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

/// Decides for the gesture recognizers of the chat table, kept apart from the controller as the
/// controller is also the delegate of other gesture recognizers, which must not be affected.
final class ChatRowGestureDelegate: NSObject, UIGestureRecognizerDelegate {

    var shouldBegin: ((UIGestureRecognizer) -> Bool)?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return self.shouldBegin?(gestureRecognizer) ?? false
    }

    // The table handles touches itself (selection, context menu), and so do the views in a cell
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

/// What the selection mode replaces in the chat, to bring it back when the mode ends.
struct SelectionSavedChrome {
    let titleView: UIView?
    let leftBarButtonItems: [UIBarButtonItem]?
    let rightBarButtonItems: [UIBarButtonItem]?
    let hidesBackButton: Bool
    let leftItemsSupplementBackButton: Bool
    let isInputbarHidden: Bool
}

// MARK: - Taps and long presses on a row

/// The two zones of a row: the bubble (and the avatar) keeps everything it did, a tap on the rest of the
/// row shows the menu of the message, and a long press there starts the selection mode.
/// In the selection mode a tap anywhere on a row picks or drops the message.
extension BaseChatViewController {

    func setUpMessageSelectionGestures() {
        guard self.supportsMessageSelection, let tableView = self.tableView else { return }

        let gestureDelegate = ChatRowGestureDelegate()
        gestureDelegate.shouldBegin = { [weak self] gestureRecognizer in
            return self?.shouldBeginRowGesture(gestureRecognizer) ?? false
        }

        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleRowTap(_:)))
        tapRecognizer.cancelsTouchesInView = false
        tapRecognizer.delegate = gestureDelegate

        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleRowLongPress(_:)))
        longPressRecognizer.delegate = gestureDelegate

        tableView.addGestureRecognizer(tapRecognizer)
        tableView.addGestureRecognizer(longPressRecognizer)

        let menuInteraction = UIEditMenuInteraction(delegate: self)
        tableView.addInteraction(menuInteraction)

        self.rowGestureDelegate = gestureDelegate
        self.rowTapRecognizer = tapRecognizer
        self.rowLongPressRecognizer = longPressRecognizer
        self.messageEditMenuInteraction = menuInteraction
    }

    private func rowTarget(at point: CGPoint) -> (indexPath: IndexPath, cell: BaseChatTableViewCell, message: NCChatMessage)? {
        guard let tableView = self.tableView,
              let indexPath = tableView.indexPathForRow(at: point),
              let cell = tableView.cellForRow(at: indexPath) as? BaseChatTableViewCell,
              let message = self.message(for: indexPath)
        else { return nil }

        return (indexPath, cell, message)
    }

    private func zone(of cell: BaseChatTableViewCell, at point: CGPoint) -> ChatRowZone {
        guard let tableView = self.tableView else { return .content }

        return ChatRowZone.zone(at: tableView.convert(point, to: cell), interactiveFrames: cell.interactiveFrames())
    }

    private func shouldBeginRowGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let tableView = self.tableView else { return false }

        let point = gestureRecognizer.location(in: tableView)

        guard let target = self.rowTarget(at: point) else { return false }

        if gestureRecognizer === self.rowLongPressRecognizer {
            return !self.messageSelection.isActive && self.canSelect(target.message) && self.zone(of: target.cell, at: point) == .empty
        }

        if gestureRecognizer === self.rowTapRecognizer {
            return self.messageSelection.isActive || (self.hasMenu(target.message) && self.zone(of: target.cell, at: point) == .empty)
        }

        return false
    }

    @objc func handleRowTap(_ gestureRecognizer: UITapGestureRecognizer) {
        guard gestureRecognizer.state == .ended, let tableView = self.tableView else { return }

        let point = gestureRecognizer.location(in: tableView)

        guard let target = self.rowTarget(at: point) else { return }

        if self.messageSelection.isActive {
            self.toggleSelection(of: target.message)
            return
        }

        guard self.hasMenu(target.message), self.zone(of: target.cell, at: point) == .empty else { return }

        self.textView.resignFirstResponder()

        self.editMenuIndexPath = target.indexPath
        self.messageEditMenuInteraction?.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: point))
    }

    @objc func handleRowLongPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
        guard gestureRecognizer.state == .began, let tableView = self.tableView,
              let target = self.rowTarget(at: gestureRecognizer.location(in: tableView))
        else { return }

        self.beginSelectionMode(with: target.message)
    }
}

// MARK: - Menu shown by a tap

extension BaseChatViewController: UIEditMenuInteractionDelegate {

    public func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let indexPath = self.editMenuIndexPath, let message = self.message(for: indexPath), self.hasMenu(message) else { return nil }

        return self.messageMenu(for: message, at: indexPath)
    }

    public func editMenuInteraction(_ interaction: UIEditMenuInteraction, willDismissMenuFor configuration: UIEditMenuConfiguration, animator: any UIEditMenuInteractionAnimating) {
        animator.addCompletion { [weak self] in
            // Wait until the menu is completely hidden before we execute any method, like for the context menu
            if let contextMenuActionBlock = self?.contextMenuActionBlock {
                contextMenuActionBlock()
                self?.contextMenuActionBlock = nil
            }
        }
    }
}

// MARK: - Selection mode

extension BaseChatViewController {

    func canSelect(_ message: NCChatMessage) -> Bool {
        return MessageSelection.isSelectable(messageId: message.messageId, isSystemMessage: message.isSystemMessage, isDeletedMessage: message.isDeletedMessage)
    }

    func beginSelectionMode(with message: NCChatMessage) {
        guard self.messageSelection.begin(with: message.messageId, isSelectable: self.canSelect(message)) else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        self.textView.resignFirstResponder()
        self.enterSelectionChrome()
        self.updateSelectionUI()
    }

    func toggleSelection(of message: NCChatMessage) {
        // A group is picked as a whole: dropping its row drops every file of it, also one picked before the rest arrived
        let ids = self.fileMessageGroup(of: message)?.messages.map { $0.messageId } ?? [message.messageId]
        let idsToToggle = self.isSelected(message) ? ids.filter { self.messageSelection.contains($0) } : [message.messageId]
        var changed = false

        for id in idsToToggle {
            changed = self.messageSelection.toggle(id, isSelectable: self.canSelect(message)) || changed
        }

        if changed {
            self.updateSelectionUI()
        }
    }

    private func fileMessageGroup(of message: NCChatMessage) -> FileMessageGroup? {
        return FileMessageGroup.containing(messageId: message.messageId, in: self.fileMessageGroups, hiddenMessageIds: self.messageIdsHiddenInFileGroups)
    }

    /// Whether the row of the message is picked: for a group, when any file of it is
    func isSelected(_ message: NCChatMessage) -> Bool {
        let ids = self.fileMessageGroup(of: message)?.messages.map { $0.messageId } ?? [message.messageId]
        return ids.contains { self.messageSelection.contains($0) }
    }

    func endSelectionMode() {
        self.messageSelection.clear()
        self.updateSelectionUI()
    }

    /// The selected messages with all files of the groups among them: a group is one row, picked by one message.
    func selectedMessagesWithFileGroups() -> [NCChatMessage] {
        return FileMessageGroup.expandingSelection(self.selectedMessages(), in: self.fileMessageGroups, hiddenMessageIds: self.messageIdsHiddenInFileGroups)
    }

    /// The selected messages that are still in the chat, from the oldest
    func selectedMessages() -> [NCChatMessage] {
        var allMessages: [NCChatMessage] = []

        for sectionDate in self.dateSections {
            allMessages.append(contentsOf: self.messages[sectionDate] ?? [])
        }

        self.messageSelection.prune(to: allMessages, id: { $0.messageId }, isSelectable: { self.canSelect($0) })

        return self.messageSelection.selectedItems(of: allMessages, id: { $0.messageId }, isSelectable: { self.canSelect($0) })
    }

    private func updateSelectionUI() {
        let selectedMessages = self.selectedMessages()

        for case let cell as BaseChatTableViewCell in self.tableView?.visibleCells ?? [] {
            cell.setSelectionMode(self.messageSelection.isActive, selected: cell.message.map { self.isSelected($0) } ?? false)
        }

        guard self.messageSelection.isActive else {
            self.exitSelectionChrome()
            return
        }

        self.selectionTitleLabel?.text = String.localizedStringWithFormat(NSLocalizedString("%ld selected", comment: "Number of messages selected in a chat, e.g. '3 selected'"), selectedMessages.count)
        self.selectionTitleLabel?.sizeToFit()

        let canForward = self.forwardPlan(for: FileMessageGroup.expandingSelection(selectedMessages, in: self.fileMessageGroups, hiddenMessageIds: self.messageIdsHiddenInFileGroups)) != nil

        for item in self.selectionToolbar?.items ?? [] {
            item.isEnabled = item.tag == selectionForwardItemTag ? canForward : true
        }
    }

    // MARK: Navigation bar and action bar

    private func enterSelectionChrome() {
        guard self.selectionSavedChrome == nil else { return }

        let navigationItem = self.navigationItem

        self.selectionSavedChrome = SelectionSavedChrome(titleView: navigationItem.titleView,
                                                         leftBarButtonItems: navigationItem.leftBarButtonItems,
                                                         rightBarButtonItems: navigationItem.rightBarButtonItems,
                                                         hidesBackButton: navigationItem.hidesBackButton,
                                                         leftItemsSupplementBackButton: navigationItem.leftItemsSupplementBackButton,
                                                         isInputbarHidden: self.textInputbar.isHidden)

        let titleLabel = UILabel()
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = NCAppBranding.themeTextColor()
        self.selectionTitleLabel = titleLabel

        let closeButton = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.endSelectionMode()
        })

        if #unavailable(iOS 26.0) {
            closeButton.tintColor = NCAppBranding.themeTextColor()
        }

        navigationItem.titleView = titleLabel
        navigationItem.hidesBackButton = true
        navigationItem.leftItemsSupplementBackButton = false
        navigationItem.leftBarButtonItems = [closeButton]
        navigationItem.rightBarButtonItems = nil

        self.textInputbar.isHidden = true

        let forwardItem = UIBarButtonItem(title: NSLocalizedString("Forward", comment: ""), primaryAction: UIAction { [weak self] _ in
            self?.didPressForwardSelected()
        })
        forwardItem.tag = selectionForwardItemTag

        let copyItem = UIBarButtonItem(title: NSLocalizedString("Copy", comment: ""), primaryAction: UIAction { [weak self] _ in
            self?.didPressCopySelected()
        })

        let toolbar = UIToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.items = [forwardItem, UIBarButtonItem(systemItem: .flexibleSpace), copyItem]
        self.view.addSubview(toolbar)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])

        self.selectionToolbar = toolbar
    }

    private func exitSelectionChrome() {
        guard let savedChrome = self.selectionSavedChrome else { return }

        let navigationItem = self.navigationItem

        navigationItem.titleView = savedChrome.titleView
        navigationItem.hidesBackButton = savedChrome.hidesBackButton
        navigationItem.leftItemsSupplementBackButton = savedChrome.leftItemsSupplementBackButton
        navigationItem.leftBarButtonItems = savedChrome.leftBarButtonItems
        navigationItem.rightBarButtonItems = savedChrome.rightBarButtonItems

        self.textInputbar.isHidden = savedChrome.isInputbarHidden

        self.selectionToolbar?.removeFromSuperview()
        self.selectionToolbar = nil
        self.selectionTitleLabel = nil
        self.selectionSavedChrome = nil
    }

    // MARK: Actions

    private func forwardKind(of message: NCChatMessage) -> ForwardKind {
        if message.poll != nil { return .poll }
        if message.file() != nil { return .file }

        return message.isObjectShare ? .objectShare : .text
    }

    /// Files can't be forwarded here, so they are left out of the forward
    private func forwardPlan(for messages: [NCChatMessage]) -> ForwardPlan? {
        return ForwardPlan.make(candidates: messages.map { ForwardPlan.Entry(id: $0.messageId, kind: self.forwardKind(of: $0)) },
                                isClassified: self.room.isClassified,
                                supportsFiles: false)
    }

    /// One message is forwarded as in its menu. Several are forwarded one by one, in the order of the chat.
    private func didPressForwardSelected() {
        let selectedMessages = self.selectedMessagesWithFileGroups()

        guard let plan = self.forwardPlan(for: selectedMessages) else {
            self.updateSelectionUI()
            return
        }

        self.endSelectionMode()

        if selectedMessages.count == 1, let message = selectedMessages.first {
            self.didPressForward(for: message)
            return
        }

        let messagesById = Dictionary(selectedMessages.map { ($0.messageId, $0) }, uniquingKeysWith: { first, _ in first })
        let items = plan.entries.compactMap { messagesById[$0.id] }.map {
            ForwardItem(text: $0.parsedMessage().string, richObject: $0.isObjectShare ? $0.richObjectFromObjectShare : nil)
        }

        self.didPressForward(items: items, skippedFiles: plan.skippedFiles)
    }

    private func didPressCopySelected() {
        let selectedMessages = self.selectedMessagesWithFileGroups()

        guard !selectedMessages.isEmpty else {
            self.updateSelectionUI()
            return
        }

        self.endSelectionMode()
        self.didPressCopy(messages: selectedMessages)
    }
}

private let selectionForwardItemTag = 1
