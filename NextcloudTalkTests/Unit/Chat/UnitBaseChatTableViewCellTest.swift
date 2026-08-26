//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitBaseChatTableViewCellTest: TestBaseRealm {

    // MARK: - Reactions

    private func makeReactionsView(inContainerOfWidth width: CGFloat) -> (container: UIView, reactionsView: ReactionsView) {
        // Mirrors how BaseChatTableViewCell.showReactionsPart() builds and constrains the view: the
        // collection view is sized by its own intrinsic content size, capped by the available width.
        let container = UIView(frame: .init(x: 0, y: 0, width: width, height: 40))
        let flowLayout = UICollectionViewFlowLayout()
        flowLayout.scrollDirection = .horizontal

        let reactionsView = ReactionsView(frame: .init(x: 0, y: 0, width: 50, height: 30), collectionViewLayout: flowLayout)
        reactionsView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(reactionsView)

        NSLayoutConstraint.activate([
            reactionsView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            reactionsView.topAnchor.constraint(equalTo: container.topAnchor),
            reactionsView.heightAnchor.constraint(equalToConstant: 30),
            reactionsView.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor)
        ])

        return (container, reactionsView)
    }

    private func reactions(_ emojis: [String]) -> [NCChatReaction] {
        return emojis.map { NCChatReaction(reaction: $0, count: 1, userReacted: false, state: .set) }
    }

    // A cell keeps its ReactionsView across reuse, so showing a message with more reactions than the
    // previous one must widen it again. Otherwise the collection view stays at the width of whatever
    // it showed before and silently clips the rest, which is only reachable by scrolling.
    func testReactionsViewWidthFollowsTheReactionsItShows() throws {
        let (container, reactionsView) = makeReactionsView(inContainerOfWidth: 1000)

        reactionsView.updateReactions(reactions: reactions(["👍", "❤️"]))
        container.setNeedsLayout()
        container.layoutIfNeeded()
        let widthForTwo = reactionsView.frame.width

        reactionsView.updateReactions(reactions: reactions(["👍", "❤️", "😀", "🎉", "🚀"]))
        container.setNeedsLayout()
        container.layoutIfNeeded()
        let widthForFive = reactionsView.frame.width

        XCTAssertGreaterThan(widthForFive, widthForTwo,
                             "Showing more reactions must widen the view, not clip them")
        XCTAssertEqual(widthForFive, reactionsView.collectionViewLayout.collectionViewContentSize.width, accuracy: 0.5,
                       "With enough room available, all reactions must fit without scrolling")

        reactionsView.updateReactions(reactions: reactions(["👍"]))
        container.setNeedsLayout()
        container.layoutIfNeeded()
        XCTAssertLessThan(reactionsView.frame.width, widthForTwo,
                          "Showing fewer reactions must shrink the view again")
    }

    // A reused view must not keep the scroll position of the message it showed before, or the first
    // reactions of the new message start off screen.
    func testReactionsViewResetsScrollPositionOnReuse() throws {
        let (container, reactionsView) = makeReactionsView(inContainerOfWidth: 120)

        reactionsView.updateReactions(reactions: reactions(["👍", "❤️", "😀", "🎉", "🚀"]))
        container.setNeedsLayout()
        container.layoutIfNeeded()

        reactionsView.setContentOffset(.init(x: 80, y: 0), animated: false)
        XCTAssertEqual(reactionsView.contentOffset.x, 80)

        reactionsView.updateReactions(reactions: reactions(["🚀", "🎉", "😀"]))
        container.setNeedsLayout()
        container.layoutIfNeeded()

        XCTAssertEqual(reactionsView.contentOffset.x, 0,
                       "A view showing another message's reactions must start at the first one")
    }

    func testSharedDeckCardQuote() throws {
        let deckObject = """
{
    "actor": {
        "type": "user",
        "id": "admin",
        "name": "admin"
    },
    "object": {
        "id": "9810",
        "name": "Test",
        "boardname": "Persönlich",
        "stackname": "Offen",
        "link": "https://nextcloud-mm.local/apps/deck/card/9810",
        "type": "deck-card",
        "icon-url": "https://nextcloud-mm.local/ocs/v2.php/apps/spreed/api/v1/room/123/avatar?v=abc"
    }
}
"""

        updateCapabilities { cap in
            cap.referenceApiSupported = true
        }

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomToken = "token"

        let room = NCRoom()
        room.token = roomToken
        room.accountId = activeAccount.accountId

        let deckMessage = NCChatMessage()
        deckMessage.messageId = 1
        deckMessage.internalId = "internal-1"
        deckMessage.token = roomToken
        deckMessage.message = "existing"
        deckMessage.messageParametersJSONString = deckObject

        // Chat message with a quote
        let quoteMessage = NCChatMessage()
        quoteMessage.message = "test"
        quoteMessage.token = roomToken
        quoteMessage.parentId = "internal-1"

        try? realm.transaction {
            realm.add(room)
            realm.add(deckMessage)
            realm.add(quoteMessage)
        }

        let deckCell: BaseChatTableViewCell = .fromNib()
        deckCell.setup(for: deckMessage, inRoom: room, forThread: nil, withAccount: activeAccount)

        let quoteCell: BaseChatTableViewCell = .fromNib()
        quoteCell.setup(for: quoteMessage, inRoom: room, forThread: nil, withAccount: activeAccount)
    }

}
