//
// Copyright (c) 2023 Marcel Müller <marcel.mueller@nextcloud.com>
//
// Author Marcel Müller <marcel.mueller@nextcloud.com>
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

       // removeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { [weak self] _ in
     //       self?.checkInactiveTypingUsers()
     //   })
    }

    deinit {
        self.removeTimer?.invalidate()
    }

    private func getUsersTypingString() -> NSAttributedString {
        // Array keep the order of the elements, no need to sort here manually
        if self.typingUsers.count == 1 {
            // Alice
            return self.typingUsers[0].displayName.withTextColor(.secondaryLabel)

        } else {
            let separator = ", ".withTextColor(.tertiaryLabel)
            let separatorSpace = NSAttributedString(string: " ")
            let separatorLast = NSLocalizedString("and", comment: "Alice and Bob").withTextColor(.tertiaryLabel)

            if self.typingUsers.count == 2 {
                // Alice and Bob
                let user1 = self.typingUsers[0].displayName.withTextColor(.secondaryLabel)
                let user2 = self.typingUsers[1].displayName.withTextColor(.secondaryLabel)

                return user1 + separatorSpace + separatorLast + separatorSpace + user2

            } else if self.typingUsers.count == 3 {
                // Alice, Bob and Charlie
                let user1 = self.typingUsers[0].displayName.withTextColor(.secondaryLabel)
                let user2 = self.typingUsers[1].displayName.withTextColor(.secondaryLabel)
                let user3 = self.typingUsers[2].displayName.withTextColor(.secondaryLabel)

                return user1 + separator + user2 + separatorSpace + separatorLast + separatorSpace + user3

            } else {
                // Alice, Bob, Charlie
                let user1 = self.typingUsers[0].displayName.withTextColor(.secondaryLabel)
                let user2 = self.typingUsers[1].displayName.withTextColor(.secondaryLabel)
                let user3 = self.typingUsers[2].displayName.withTextColor(.secondaryLabel)

                return user1 + separator + user2 + separator + user3
            }
        }
    }

    private func updateTypingIndicator() {
        if self.typingUsers.isEmpty {
            // Just hide the label to have a nice animation. Otherwise we would animate an empty label/space
            self.isVisible = false
        } else {
            let attributedSpace = NSAttributedString(string: " ")
            var localizedSuffix: NSAttributedString

            if self.typingUsers.count == 1 {
                localizedSuffix = NSLocalizedString("is typing…", comment: "Alice is typing…").withTextColor(.tertiaryLabel)

            } else if self.typingUsers.count == 2 || self.typingUsers.count == 3 {
                localizedSuffix = NSLocalizedString("are typing…", comment: "Alice and Bob are typing…").withTextColor(.tertiaryLabel)

            } else if self.typingUsers.count == 4 {
                localizedSuffix = NSLocalizedString("and 1 other is typing…", comment: "Alice, Bob, Charlie and 1 other is typing…").withTextColor(.tertiaryLabel)

            } else {
                let localizedString = NSLocalizedString("and %ld others are typing…", comment: "Alice, Bob, Charlie and 3 others are typing…")
                let formattedString = String(format: localizedString, self.typingUsers.count - 3)
                localizedSuffix = formattedString.withTextColor(.tertiaryLabel)
            }

            UIView.transition(with: self.typingLabel,
                              duration: 0.2,
                              options: .transitionCrossDissolve,
                              animations: {
                self.typingLabel.attributedText = self.getUsersTypingString() + attributedSpace + localizedSuffix
            }, completion: nil)

            self.isVisible = true
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
