//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Combine
import SwiftyAttributes

@objcMembers class TypingIndicatorView: UIView, SLKVisibleViewProtocol {
    private class TypingUser {
        var userIdentifier: String
        var displayName: String
        var lastUpdate: TimeInterval

        init(userIdentifier: String, displayName: String) {
            self.userIdentifier = userIdentifier
            self.displayName = displayName
            self.lastUpdate = Date().timeIntervalSinceReferenceDate
        }

        public func updateTimestamp() {
            self.lastUpdate = Date().timeIntervalSinceReferenceDate
        }
    }

    dynamic var isVisible: Bool = false

    private var typingUsers: [TypingUser] = []
    private var previousUpdateTimestamp: TimeInterval = .zero
    private var updateTimer: Timer?
    private var removeTimer: Timer?

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var typingLabel: UILabel!

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    func commonInit() {
        Bundle.main.loadNibNamed("TypingIndicatorView", owner: self, options: nil)
        addSubview(contentView)
        contentView.frame = frame
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.backgroundColor = .clear

        typingLabel.text = ""

        removeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { [weak self] _ in
            self?.checkInactiveTypingUsers()
        })
    }

    deinit {
        self.removeTimer?.invalidate()
    }

    internal func updateTypingIndicator() {
        if self.typingUsers.isEmpty {
            // Just hide the label to have a nice animation. Otherwise we would animate an empty label/space
            self.isVisible = false
        } else {
            var localizedAttributedString: NSAttributedString?

            if self.typingUsers.count == 1 {
                let unformattedAttributedString = NSLocalizedString("%@ is typing…", comment: "Alice is typing…").withTextColor(.tertiaryLabel)
                localizedAttributedString = NSAttributedString(format: unformattedAttributedString,
                                                               self.typingUsers[0].displayName.withTextColor(.secondaryLabel))

            } else if self.typingUsers.count == 2 {
                let unformattedAttributedString = NSLocalizedString("%1$@ and %2$@ are typing…", comment: "Alice and Bob are typing…").withTextColor(.tertiaryLabel)
                localizedAttributedString = NSAttributedString(format: unformattedAttributedString,
                                                               self.typingUsers[0].displayName.withTextColor(.secondaryLabel),
                                                               self.typingUsers[1].displayName.withTextColor(.secondaryLabel))

            } else if self.typingUsers.count == 3 {
                let unformattedAttributedString = NSLocalizedString("%1$@, %2$@ and %3$@ are typing…", comment: "Alice, Bob and Charlie are typing…").withTextColor(.tertiaryLabel)
                localizedAttributedString = NSAttributedString(format: unformattedAttributedString,
                                                               self.typingUsers[0].displayName.withTextColor(.secondaryLabel),
                                                               self.typingUsers[1].displayName.withTextColor(.secondaryLabel),
                                                               self.typingUsers[2].displayName.withTextColor(.secondaryLabel))

            } else if self.typingUsers.count == 4 {
                let unformattedAttributedString = NSLocalizedString("%1$@, %2$@, %3$@ and 1 other is typing…", comment: "Alice, Bob, Charlie and 1 other is typing…").withTextColor(.tertiaryLabel)
                localizedAttributedString = NSAttributedString(format: unformattedAttributedString,
                                                               self.typingUsers[0].displayName.withTextColor(.secondaryLabel),
                                                               self.typingUsers[1].displayName.withTextColor(.secondaryLabel),
                                                               self.typingUsers[2].displayName.withTextColor(.secondaryLabel))
            } else {
                let othersCount = self.typingUsers.count - 3
                let unformattedAttributedString = NSLocalizedString("%1$@, %2$@, %3$@ and %4$@ others are typing…", comment: "Alice, Bob, Charlie and 3 others are typing…").withTextColor(.tertiaryLabel)
                localizedAttributedString = NSAttributedString(format: unformattedAttributedString,
                                                               self.typingUsers[0].displayName.withTextColor(.secondaryLabel),
                                                               self.typingUsers[1].displayName.withTextColor(.secondaryLabel),
                                                               self.typingUsers[2].displayName.withTextColor(.secondaryLabel),
                                                               othersCount)
            }

            if let localizedAttributedString {
                UIView.transition(with: self.typingLabel,
                                  duration: 0.2,
                                  options: .transitionCrossDissolve,
                                  animations: {
                    self.typingLabel.attributedText = localizedAttributedString.withFont(.preferredFont(forTextStyle: .body))
                }, completion: nil)

                self.isVisible = true
            } else {
                self.isVisible = false
            }
        }

        self.previousUpdateTimestamp = Date().timeIntervalSinceReferenceDate
    }

    private func updateTypingIndicatorDebounced() {
        // There's already an update planned, no need to do that again
        if updateTimer != nil {
            return
        }

        let currentUpdateTimestamp: TimeInterval = Date().timeIntervalSinceReferenceDate

        // Update the typing indicator at max. every second
        let timestampDiff = currentUpdateTimestamp - previousUpdateTimestamp
        if timestampDiff < 1.0 {
            self.updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 - timestampDiff, repeats: false, block: { _ in
                self.updateTypingIndicator()
                self.updateTimer = nil
            })
        } else {
            self.updateTypingIndicator()
        }
    }

    func checkInactiveTypingUsers() {
        let currentUpdateTimestamp: TimeInterval = Date().timeIntervalSinceReferenceDate
        var usersToRemove: [TypingUser] = []

        for typingUser in typingUsers {
            let timestampDiff = currentUpdateTimestamp - typingUser.lastUpdate

            if timestampDiff >= 15 {
                // We did not receive an update for that user in the last 15 seconds -> remove it
                usersToRemove.append(typingUser)
            }
        }

        // Remove the users. Do that after iterating typingUsers to not alter the collection while iterating
        for typingUser in usersToRemove {
            self.removeTyping(userIdentifier: typingUser.userIdentifier)
        }
    }

    func addTyping(userIdentifier: String, displayName: String) {
        let existingEntry = self.typingUsers.first(where: { $0.userIdentifier == userIdentifier })

        if existingEntry == nil {
            let newEntry = TypingUser(userIdentifier: userIdentifier, displayName: displayName)
            self.typingUsers.append(newEntry)
        } else {
            // We received another startedTyping message, so we want to restart the remove timer
            existingEntry?.updateTimestamp()
        }

        self.updateTypingIndicatorDebounced()
    }

    func removeTyping(userIdentifier: String) {
        let existingIndex = self.typingUsers.firstIndex(where: { $0.userIdentifier == userIdentifier })

        if let existingIndex = existingIndex {
            self.typingUsers.remove(at: existingIndex)
        }

        self.updateTypingIndicatorDebounced()
    }
}
