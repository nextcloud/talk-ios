//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

/// The zones of a chat row, and the messages picked in the selection mode.
final class UnitMessageSelectionTest: TestBaseRealm {

    // MARK: - Zone of a touch

    private let bubble = CGRect(x: 100, y: 10, width: 200, height: 60)
    private let avatar = CGRect(x: 10, y: 10, width: 30, height: 30)

    func testTouchOnTheBubbleIsContent() {
        XCTAssertEqual(ChatRowZone.zone(at: CGPoint(x: 200, y: 40), interactiveFrames: [bubble, avatar]), .content)
        XCTAssertEqual(ChatRowZone.zone(at: CGPoint(x: 100, y: 10), interactiveFrames: [bubble, avatar]), .content, "The edge belongs to the bubble")
    }

    func testTouchOnTheAvatarIsContent() {
        XCTAssertEqual(ChatRowZone.zone(at: CGPoint(x: 20, y: 20), interactiveFrames: [bubble, avatar]), .content)
    }

    func testTouchNextToTheBubbleIsEmpty() {
        XCTAssertEqual(ChatRowZone.zone(at: CGPoint(x: 350, y: 40), interactiveFrames: [bubble, avatar]), .empty, "Right of the bubble")
        XCTAssertEqual(ChatRowZone.zone(at: CGPoint(x: 60, y: 40), interactiveFrames: [bubble, avatar]), .empty, "Between avatar and bubble")
        XCTAssertEqual(ChatRowZone.zone(at: CGPoint(x: 200, y: 90), interactiveFrames: [bubble, avatar]), .empty, "Below the bubble")
        XCTAssertEqual(ChatRowZone.zone(at: CGPoint(x: 20, y: 60), interactiveFrames: [bubble, avatar]), .empty, "Below the avatar, in a row taller than it")
        XCTAssertEqual(ChatRowZone.zone(at: CGPoint(x: 5, y: 5), interactiveFrames: []), .empty)
    }

    // The frames come from a real cell: own messages are on the right and have no avatar, the others have one
    private func cell(isOwnMessage: Bool, reactions: [String: Int]? = nil) throws -> BaseChatTableViewCell {
        let account = NCDatabaseManager.sharedInstance().activeAccount()
        let room = NCRoom(value: self.addRoom(withToken: "token", withName: "Room"))

        var dict: [String: Any] = [
            "id": 1,
            "token": "token",
            "message": "Hello",
            "messageType": "comment",
            "systemMessage": "",
            "actorId": isOwnMessage ? account.userId : "someone-else",
            "actorType": "users"
        ]

        if let reactions {
            dict["reactions"] = reactions
        }

        let message = try XCTUnwrap(NCChatMessage(dictionary: dict, andAccountId: account.accountId))
        let cell = try XCTUnwrap(UINib(nibName: BaseChatTableViewCell.nibName, bundle: nil)
            .instantiate(withOwner: nil).first as? BaseChatTableViewCell)

        cell.frame = .init(x: 0, y: 0, width: 400, height: 200)
        cell.setup(for: message, inRoom: room, forThread: nil, withAccount: account)
        cell.layoutIfNeeded()

        return cell
    }

    func testCellOfOwnMessageHasEmptyZoneLeftOfTheBubble() throws {
        let cell = try cell(isOwnMessage: true)
        let frames = cell.interactiveFrames()
        let bubbleFrame = cell.convert(cell.bubbleStackView.bounds, from: cell.bubbleStackView)

        XCTAssertTrue(frames.contains(bubbleFrame))
        XCTAssertEqual(ChatRowZone.zone(at: CGPoint(x: bubbleFrame.midX, y: bubbleFrame.midY), interactiveFrames: frames), .content)
        XCTAssertEqual(ChatRowZone.zone(at: CGPoint(x: 5, y: bubbleFrame.midY), interactiveFrames: frames), .empty)
    }

    // The reactions are part of the bubble, so a tap or long press on them keeps what it did
    func testReactionsOfARealCellLieInsideTheBubbleAndAreContent() throws {
        let cell = try cell(isOwnMessage: true, reactions: ["👍": 2])
        let bubbleFrame = cell.convert(cell.bubbleStackView.bounds, from: cell.bubbleStackView)
        let reactionsFrame = cell.convert(cell.reactionPart.bounds, from: cell.reactionPart)

        XCTAssertFalse(cell.reactionPart.isHidden)
        XCTAssertTrue(bubbleFrame.contains(reactionsFrame), "The reactions are inside of the bubble")
        XCTAssertEqual(ChatRowZone.zone(at: CGPoint(x: reactionsFrame.midX, y: reactionsFrame.midY), interactiveFrames: cell.interactiveFrames()), .content)
    }

    func testCellOfOtherMessageHasEmptyZoneRightOfTheBubbleAndAvatarIsContent() throws {
        let cell = try cell(isOwnMessage: false)
        let frames = cell.interactiveFrames()
        let bubbleFrame = cell.convert(cell.bubbleStackView.bounds, from: cell.bubbleStackView)
        let avatarFrame = cell.convert(cell.avatarButton.bounds, from: cell.avatarButton)

        XCTAssertFalse(cell.avatarButton.isHidden)
        XCTAssertEqual(ChatRowZone.zone(at: CGPoint(x: avatarFrame.midX, y: avatarFrame.midY), interactiveFrames: frames), .content)
        XCTAssertEqual(ChatRowZone.zone(at: CGPoint(x: bubbleFrame.midX, y: bubbleFrame.midY), interactiveFrames: frames), .content)
        XCTAssertEqual(ChatRowZone.zone(at: CGPoint(x: cell.bounds.width - 5, y: bubbleFrame.midY), interactiveFrames: frames), .empty)
    }

    // MARK: - Selection

    func testSelectionStartsWithOneMessage() {
        var selection = MessageSelection()

        XCTAssertFalse(selection.isActive)
        XCTAssertEqual(selection.count, 0)

        XCTAssertTrue(selection.begin(with: 5, isSelectable: true))

        XCTAssertTrue(selection.isActive)
        XCTAssertEqual(selection.count, 1)
        XCTAssertTrue(selection.contains(5))
    }

    func testSelectionDoesNotStartWithAMessageThatCantBeSelected() {
        var selection = MessageSelection()

        XCTAssertFalse(selection.begin(with: 5, isSelectable: false))

        XCTAssertFalse(selection.isActive)
        XCTAssertEqual(selection.count, 0)
    }

    func testToggleSelectsAndDeselectsAndCounts() {
        var selection = MessageSelection()
        selection.begin(with: 1, isSelectable: true)

        XCTAssertTrue(selection.toggle(2, isSelectable: true))
        XCTAssertTrue(selection.toggle(3, isSelectable: true))
        XCTAssertEqual(selection.count, 3)

        XCTAssertTrue(selection.toggle(2, isSelectable: true))
        XCTAssertEqual(selection.count, 2)
        XCTAssertFalse(selection.contains(2))
        XCTAssertTrue(selection.isActive)
    }

    func testDeselectingTheLastMessageEndsTheMode() {
        var selection = MessageSelection()
        selection.begin(with: 1, isSelectable: true)
        selection.toggle(2, isSelectable: true)

        selection.toggle(1, isSelectable: true)
        XCTAssertTrue(selection.isActive)

        selection.toggle(2, isSelectable: true)
        XCTAssertFalse(selection.isActive)
        XCTAssertEqual(selection.count, 0)
    }

    func testToggleDoesNothingOutsideOfTheModeOrForAMessageThatCantBeSelected() {
        var selection = MessageSelection()

        XCTAssertFalse(selection.toggle(1, isSelectable: true), "A tap outside of the mode does not start it")
        XCTAssertFalse(selection.isActive)

        selection.begin(with: 1, isSelectable: true)

        XCTAssertFalse(selection.toggle(2, isSelectable: false))
        XCTAssertEqual(selection.count, 1)
        XCTAssertFalse(selection.contains(2))
    }

    func testClearEndsTheMode() {
        var selection = MessageSelection()
        selection.begin(with: 1, isSelectable: true)
        selection.toggle(2, isSelectable: true)

        selection.clear()

        XCTAssertFalse(selection.isActive)
        XCTAssertEqual(selection.count, 0)
        XCTAssertFalse(selection.contains(1))
    }

    func testPruneDropsMessagesThatLeftTheChatAndEndsTheModeWhenNoneIsLeft() {
        var selection = MessageSelection()
        selection.begin(with: 1, isSelectable: true)
        selection.toggle(2, isSelectable: true)

        selection.prune(to: [2, 3], id: { $0 }, isSelectable: { _ in true })
        XCTAssertEqual(selection.selectedIds, [2])
        XCTAssertTrue(selection.isActive)

        selection.prune(to: [3], id: { $0 }, isSelectable: { _ in true })
        XCTAssertFalse(selection.isActive)
        XCTAssertEqual(selection.count, 0)
    }

    func testMessageDeletedAfterItWasSelectedIsPrunedSoDeselectingTheLastLiveOneEndsTheMode() {
        var selection = MessageSelection()
        selection.begin(with: 1, isSelectable: true)
        selection.toggle(2, isSelectable: true)

        // Message 2 is still in the chat, but deleted now
        let deleted: Set<Int> = [2]
        selection.prune(to: [1, 2], id: { $0 }, isSelectable: { !deleted.contains($0) })
        XCTAssertEqual(selection.selectedIds, [1])

        selection.toggle(1, isSelectable: true)
        XCTAssertFalse(selection.isActive)
        XCTAssertEqual(selection.count, 0)
    }

    // MARK: - What can be selected

    func testMessagesThatHaveNoMenuCantBeSelected() {
        XCTAssertTrue(MessageSelection.isSelectable(messageId: 10, isSystemMessage: false, isDeletedMessage: false))
        XCTAssertFalse(MessageSelection.isSelectable(messageId: 10, isSystemMessage: true, isDeletedMessage: false), "System message")
        XCTAssertFalse(MessageSelection.isSelectable(messageId: 10, isSystemMessage: false, isDeletedMessage: true), "Deleted message")

        for separatorId in [MessageSeparatorTableViewCell.unreadMessagesSeparatorId,
                            MessageSeparatorTableViewCell.unreadMessagesWithSummarySeparatorId,
                            MessageSeparatorTableViewCell.chatBlockSeparatorId] {
            XCTAssertFalse(MessageSelection.hasMenu(messageId: separatorId, isSystemMessage: false, isDeletedMessage: false), "Separator")
            XCTAssertFalse(MessageSelection.isSelectable(messageId: separatorId, isSystemMessage: false, isDeletedMessage: false), "Separator")
        }
    }

    // A message still being sent has no id yet and keeps its menu, but a selection by id could not tell such messages apart
    func testMessageWithoutServerIdHasAMenuButCantBeSelected() {
        XCTAssertTrue(MessageSelection.hasMenu(messageId: 0, isSystemMessage: false, isDeletedMessage: false))
        XCTAssertFalse(MessageSelection.isSelectable(messageId: 0, isSystemMessage: false, isDeletedMessage: false))
    }

    // MARK: - Forward

    private func entry(_ id: Int, _ kind: ForwardKind) -> ForwardPlan.Entry {
        return ForwardPlan.Entry(id: id, kind: kind)
    }

    func testForwardPlanSendsEveryMessageOnceInTheOrderOfTheChat() throws {
        let candidates = [entry(10, .text), entry(20, .objectShare), entry(30, .text)]

        let plan = try XCTUnwrap(ForwardPlan.make(candidates: candidates, isClassified: false, supportsFiles: false))

        XCTAssertEqual(plan.entries.map { $0.id }, [10, 20, 30], "One send per message, not one for all")
        XCTAssertEqual(plan.skippedFiles, 0)
    }

    func testForwardPlanLeavesFilesOutWhenTheyCantBeForwardedAndCountsThem() throws {
        let candidates = [entry(10, .text), entry(20, .file), entry(30, .text), entry(40, .file)]

        let plan = try XCTUnwrap(ForwardPlan.make(candidates: candidates, isClassified: false, supportsFiles: false))

        XCTAssertEqual(plan.entries.map { $0.id }, [10, 30])
        XCTAssertEqual(plan.skippedFiles, 2)
    }

    func testForwardPlanKeepsFilesInTheOrderOfTheChatWhenTheyCanBeForwarded() throws {
        let candidates = [entry(10, .text), entry(20, .file), entry(30, .text)]

        let plan = try XCTUnwrap(ForwardPlan.make(candidates: candidates, isClassified: false, supportsFiles: true))

        XCTAssertEqual(plan.entries.map { $0.id }, [10, 20, 30], "Text, file, text stays in this order")
        XCTAssertEqual(plan.skippedFiles, 0)
    }

    func testForwardPlanIsOffInClassifiedConversationWithAPollOrWithNothingToSend() {
        XCTAssertNil(ForwardPlan.make(candidates: [entry(10, .text)], isClassified: true, supportsFiles: true), "Classified conversation")
        XCTAssertNil(ForwardPlan.make(candidates: [entry(10, .text), entry(20, .poll)], isClassified: false, supportsFiles: true), "Poll")
        XCTAssertNil(ForwardPlan.make(candidates: [entry(10, .file), entry(20, .file)], isClassified: false, supportsFiles: false), "Only files")
        XCTAssertNil(ForwardPlan.make(candidates: [], isClassified: false, supportsFiles: true), "Nothing selected")
    }

    // MARK: - Sending one after the other

    func testSenderStartsTheNextSendOnlyWhenThePreviousOneIsDone() {
        var started: [Int] = []
        var finishers: [(Error?) -> Void] = []
        var result: (sent: Int, error: Error?)?

        SequentialSender.send([1, 2, 3], one: { item, done in
            started.append(item)
            finishers.append(done)
        }, completion: { sent, error in
            result = (sent, error)
        })

        XCTAssertEqual(started, [1], "The second send waits for the first one")

        finishers[0](nil)
        XCTAssertEqual(started, [1, 2])

        finishers[1](nil)
        XCTAssertEqual(started, [1, 2, 3])
        XCTAssertNil(result, "Not done while the last send runs")

        finishers[2](nil)
        XCTAssertEqual(result?.sent, 3)
        XCTAssertNil(result?.error)
    }

    func testSenderStopsAtTheFirstError() {
        var started: [Int] = []
        var result: (sent: Int, error: Error?)?

        SequentialSender.send([1, 2, 3], one: { item, done in
            started.append(item)
            done(item == 2 ? NSError(domain: "test", code: 1) : nil)
        }, completion: { sent, error in
            result = (sent, error)
        })

        XCTAssertEqual(started, [1, 2], "Nothing is sent after the failed one")
        XCTAssertEqual(result?.sent, 1)
        XCTAssertNotNil(result?.error)
    }

    func testSenderWithoutItemsIsDoneAtOnce() {
        var result: (sent: Int, error: Error?)?

        SequentialSender.send([Int](), one: { _, _ in XCTFail("Nothing to send") }, completion: { sent, error in
            result = (sent, error)
        })

        XCTAssertEqual(result?.sent, 0)
        XCTAssertNil(result?.error)
    }

    // MARK: - Text of several messages

    func testSelectedMessagesAreInTheOrderOfTheChat() {
        var selection = MessageSelection()
        // Picked in another order than they are in the chat
        selection.begin(with: 30, isSelectable: true)
        selection.toggle(10, isSelectable: true)
        selection.toggle(20, isSelectable: true)

        let chat = [(id: 10, text: "first"), (id: 15, text: "not picked"), (id: 20, text: "second"), (id: 30, text: "third")]

        let selected = selection.selectedItems(of: chat, id: { $0.id })

        XCTAssertEqual(selected.map { $0.text }, ["first", "second", "third"])
    }

    // A message deleted while it was selected must not be forwarded or copied as "Message deleted"
    func testMessageDeletedAfterItWasSelectedIsLeftOut() {
        var selection = MessageSelection()
        selection.begin(with: 10, isSelectable: true)
        selection.toggle(20, isSelectable: true)

        var chat = [(id: 10, text: "first", isDeleted: false), (id: 20, text: "second", isDeleted: false)]
        let isSelectable: ((id: Int, text: String, isDeleted: Bool)) -> Bool = {
            MessageSelection.isSelectable(messageId: $0.id, isSystemMessage: false, isDeletedMessage: $0.isDeleted)
        }

        XCTAssertEqual(selection.selectedItems(of: chat, id: { $0.id }, isSelectable: isSelectable).map { $0.id }, [10, 20])

        chat[1].isDeleted = true

        XCTAssertEqual(selection.selectedItems(of: chat, id: { $0.id }, isSelectable: isSelectable).map { $0.id }, [10])
    }

    // MARK: - Second answer of a send

    func testSenderIgnoresASecondAnswerOfTheSameSend() {
        var started: [Int] = []
        var finishers: [(Error?) -> Void] = []
        var results: [(sent: Int, error: Error?)] = []

        SequentialSender.send([1, 2], one: { item, done in
            started.append(item)
            finishers.append(done)
        }, completion: { sent, error in
            results.append((sent, error))
        })

        finishers[0](nil)
        finishers[0](nil)
        finishers[0](NSError(domain: "test", code: 1))

        XCTAssertEqual(started, [1, 2], "The second send starts once")
        XCTAssertTrue(results.isEmpty)

        finishers[1](nil)
        finishers[1](NSError(domain: "test", code: 1))

        XCTAssertEqual(results.count, 1, "The run ends once")
        XCTAssertEqual(results.first?.sent, 2)
        XCTAssertNil(results.first?.error)
    }

    func testSenderCountsTheSentMessagesWhenALaterOneFails() {
        var result: (sent: Int, error: Error?)?

        SequentialSender.send([1, 2, 3, 4, 5], one: { item, done in
            done(item == 3 ? NSError(domain: "test", code: 1) : nil)
        }, completion: { sent, error in
            result = (sent, error)
        })

        XCTAssertEqual(result?.sent, 2, "Two messages are out already, the user is told")
        XCTAssertNotNil(result?.error)
    }

    func testTextOfSeveralMessagesIsOneMessagePerLine() {
        XCTAssertEqual(MessageSelection.joinedText(of: ["first", "second", "third"]), "first\nsecond\nthird")
        XCTAssertEqual(MessageSelection.joinedText(of: ["only"]), "only")
        XCTAssertEqual(MessageSelection.joinedText(of: ["multi\nline", "next"]), "multi\nline\nnext")
    }
}
