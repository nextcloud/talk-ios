//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import CoreGraphics
import Foundation

/// Which part of a chat row a touch landed on.
enum ChatRowZone {

    /// The bubble with its reactions, or another element that handles touches itself (the avatar).
    case content

    /// The rest of the row, left and right of the bubble.
    case empty

    /// `interactiveFrames` are the frames of the bubble and the avatar, in the coordinate space of `point`.
    static func zone(at point: CGPoint, interactiveFrames: [CGRect]) -> ChatRowZone {
        return interactiveFrames.contains(where: { $0.contains(point) }) ? .content : .empty
    }
}

/// The messages picked in the multi-selection mode of a chat, by message id.
struct MessageSelection {

    /// Separate lines, as the messages are in the chat
    static let textSeparator = "\n"

    private(set) var selectedIds: Set<Int> = []
    private(set) var isActive = false

    var count: Int {
        return self.selectedIds.count
    }

    func contains(_ messageId: Int) -> Bool {
        return self.selectedIds.contains(messageId)
    }

    /// The messages that get a message menu: no system or deleted messages and no separators.
    static func hasMenu(messageId: Int, isSystemMessage: Bool, isDeletedMessage: Bool) -> Bool {
        return !isSystemMessage && !isDeletedMessage &&
            messageId != MessageSeparatorTableViewCell.unreadMessagesSeparatorId &&
            messageId != MessageSeparatorTableViewCell.unreadMessagesWithSummarySeparatorId &&
            messageId != MessageSeparatorTableViewCell.chatBlockSeparatorId
    }

    /// The messages with a menu, once the server knows them: a message is picked by its id, and the
    /// messages that are still being sent don't have one yet.
    static func isSelectable(messageId: Int, isSystemMessage: Bool, isDeletedMessage: Bool) -> Bool {
        return messageId > 0 && self.hasMenu(messageId: messageId, isSystemMessage: isSystemMessage, isDeletedMessage: isDeletedMessage)
    }

    /// Starts the mode with one message selected. Returns false and does nothing for a message that can't be selected.
    @discardableResult
    mutating func begin(with messageId: Int, isSelectable: Bool) -> Bool {
        guard isSelectable else { return false }

        self.selectedIds = [messageId]
        self.isActive = true

        return true
    }

    /// Selects or deselects a message. The mode ends when the last message is deselected.
    /// Returns false and does nothing outside of the mode and for a message that can't be selected.
    @discardableResult
    mutating func toggle(_ messageId: Int, isSelectable: Bool) -> Bool {
        guard self.isActive, isSelectable else { return false }

        if self.selectedIds.contains(messageId) {
            self.selectedIds.remove(messageId)
        } else {
            self.selectedIds.insert(messageId)
        }

        if self.selectedIds.isEmpty {
            self.isActive = false
        }

        return true
    }

    mutating func clear() {
        self.selectedIds = []
        self.isActive = false
    }

    /// Drops messages that are not in the chat anymore or can't be selected anymore, e.g. removed by a reload or deleted.
    /// Ends the mode when none is left.
    mutating func prune<T>(to items: [T], id: (T) -> Int, isSelectable: (T) -> Bool) {
        guard self.isActive else { return }

        self.selectedIds.formIntersection(items.filter(isSelectable).map(id))

        if self.selectedIds.isEmpty {
            self.isActive = false
        }
    }

    /// The selected items of `items`, in the order of `items` (the messages of the chat from the oldest).
    /// An item that is not selectable anymore, e.g. a message deleted while it was selected, is left out.
    func selectedItems<T>(of items: [T], id: (T) -> Int, isSelectable: (T) -> Bool = { _ in true }) -> [T] {
        return items.filter { self.selectedIds.contains(id($0)) && isSelectable($0) }
    }

    /// One text for several messages to copy, one message per line.
    static func joinedText(of texts: [String]) -> String {
        return texts.joined(separator: self.textSeparator)
    }
}
