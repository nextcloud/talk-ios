//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// One message of a forward of several messages, as the share screens need it.
@objc(NCForwardItem) public final class ForwardItem: NSObject {

    /// The text of a message, or the title of an object share
    @objc public let text: String

    /// The rich object of an object share, nil for a text
    @objc public let richObject: [String: Any]?

    @objc public init(text: String, richObject: [String: Any]? = nil) {
        self.text = text
        self.richObject = richObject
    }
}

/// What a selected message is for forwarding.
enum ForwardKind: Equatable {
    case text
    case objectShare
    case file
    case poll
}

/// Which of the selected messages are forwarded, and in which order.
struct ForwardPlan: Equatable {

    struct Entry: Equatable {
        let id: Int
        let kind: ForwardKind
    }

    /// One send per entry, in the order of the chat
    let entries: [Entry]

    /// Files that can't be forwarded and are left out
    let skippedFiles: Int

    /// `candidates` are the selected messages from the oldest. Returns nil when there is nothing to forward:
    /// in a classified conversation, with a poll among the messages (as in the menu of a message), and
    /// when only files that can't be forwarded are selected. Files are sent along only if `supportsFiles`.
    static func make(candidates: [Entry], isClassified: Bool, supportsFiles: Bool) -> ForwardPlan? {
        guard !isClassified, !candidates.contains(where: { $0.kind == .poll }) else { return nil }

        let forwardable = candidates.filter { $0.kind != .file || supportsFiles }

        guard !forwardable.isEmpty else { return nil }

        return ForwardPlan(entries: forwardable, skippedFiles: candidates.count - forwardable.count)
    }
}

/// Runs asynchronous sends strictly one after the other: the next one starts when the previous one is done,
/// so the messages arrive in the order of the list. Stops at the first error. A second answer for a send is ignored.
enum SequentialSender {

    /// `completion` gets the number of sends that succeeded and the error that stopped the run, if any.
    static func send<Item>(_ items: [Item],
                           one: @escaping (Item, @escaping (Error?) -> Void) -> Void,
                           completion: @escaping (_ sent: Int, _ error: Error?) -> Void) {
        func next(_ index: Int) {
            guard index < items.count else {
                completion(index, nil)
                return
            }

            var isDone = false

            one(items[index]) { error in
                // A second answer for the same send must neither run the next send twice nor end the run twice
                guard !isDone else { return }
                isDone = true

                if let error {
                    completion(index, error)
                } else {
                    next(index + 1)
                }
            }
        }

        next(0)
    }
}
