//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

/// The width a message body is calculated to have, against the width it is laid out at.
///
/// The chat measures a message before there is a cell to measure it with, by subtracting the
/// paddings around the bubble from the width of the row. Nothing else checks that subtraction
/// against what the cell actually does, and a calculation that comes out too wide leaves the
/// previews of a group asking for more room than they have, which autolayout takes off them again.
final class UnitChatBubbleWidthTest: TestBaseRealm {

    private lazy var room = NCRoom(value: self.addRoom(withToken: "token", withName: "Room"))

    /// The widest the body of a cell is laid out at.
    ///
    /// A bubble is otherwise as wide as what it holds, so a view that would like to be enormous is
    /// put in it. Wanting it weakly, it stretches the body to its cap without overruling anything.
    private func bodyWidth(forCellWidth cellWidth: CGFloat, isOwnMessage: Bool) throws -> CGFloat {
        let account = NCDatabaseManager.sharedInstance().activeAccount()

        let dict: [String: Any] = [
            "id": 1,
            "token": "token",
            "message": "Hello",
            "messageType": "comment",
            "systemMessage": "",
            "actorId": isOwnMessage ? account.userId : "someone-else",
            "actorType": "users"
        ]

        let message = try XCTUnwrap(NCChatMessage(dictionary: dict, andAccountId: account.accountId))

        let cell = try XCTUnwrap(UINib(nibName: BaseChatTableViewCell.nibName, bundle: nil)
            .instantiate(withOwner: nil).first as? BaseChatTableViewCell)

        cell.frame = .init(x: 0, y: 0, width: cellWidth, height: 2000)
        cell.setup(for: message, inRoom: self.room, forThread: nil, withAccount: account)

        let filler = UIView()
        filler.translatesAutoresizingMaskIntoConstraints = false
        cell.messageBodyView.addSubview(filler)

        let fillerWidth = filler.widthAnchor.constraint(equalToConstant: 10000)
        fillerWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            filler.leadingAnchor.constraint(equalTo: cell.messageBodyView.leadingAnchor),
            filler.trailingAnchor.constraint(equalTo: cell.messageBodyView.trailingAnchor),
            filler.topAnchor.constraint(equalTo: cell.messageBodyView.topAnchor),
            filler.heightAnchor.constraint(equalToConstant: 10),
            fillerWidth
        ])

        cell.layoutIfNeeded()

        return cell.messageBodyView.bounds.width
    }

    /// What `availableBodyWidth` works out for the same cell, without laying anything out
    private func calculatedBodyWidth(forCellWidth cellWidth: CGFloat, isOwnMessage: Bool) -> CGFloat {
        // The chat takes the avatar off the row before asking, and the safe area is zero here
        let rowWidth = cellWidth - chatMessageCellAvatarHeight

        return BaseChatTableViewCell.bubbleWidth(forRowWidth: rowWidth, isOwnMessage: isOwnMessage)
            - BaseChatTableViewCell.bodyHorizontalInset
    }

    func testTheCalculatedBodyWidthMatchesTheLaidOutOneForOwnMessages() throws {
        for cellWidth in [375.0, 393.0, 402.0, 440.0] {
            let laidOut = try self.bodyWidth(forCellWidth: cellWidth, isOwnMessage: true)
            let calculated = self.calculatedBodyWidth(forCellWidth: cellWidth, isOwnMessage: true)

            XCTAssertEqual(calculated, laidOut, accuracy: 0.5,
                           "At a cell width of \(cellWidth) the body is \(laidOut) wide, not \(calculated)")
        }
    }

    func testTheCalculatedBodyWidthMatchesTheLaidOutOneForOtherMessages() throws {
        for cellWidth in [375.0, 393.0, 402.0, 440.0] {
            let laidOut = try self.bodyWidth(forCellWidth: cellWidth, isOwnMessage: false)
            let calculated = self.calculatedBodyWidth(forCellWidth: cellWidth, isOwnMessage: false)

            XCTAssertEqual(calculated, laidOut, accuracy: 0.5,
                           "At a cell width of \(cellWidth) the body is \(laidOut) wide, not \(calculated)")
        }
    }

    /// Being too wide is the one that breaks: the previews of a group then ask for more room than
    /// they have, and autolayout shrinks them to fit
    func testTheCalculationIsNeverWiderThanTheBody() throws {
        for cellWidth in [320.0, 375.0, 393.0, 402.0, 440.0, 1024.0] {
            for isOwnMessage in [true, false] {
                let laidOut = try self.bodyWidth(forCellWidth: cellWidth, isOwnMessage: isOwnMessage)
                let calculated = self.calculatedBodyWidth(forCellWidth: cellWidth, isOwnMessage: isOwnMessage)

                XCTAssertLessThanOrEqual(calculated, laidOut + 0.5,
                                         "At \(cellWidth), own: \(isOwnMessage), the calculation is \(calculated - laidOut) too wide")
            }
        }
    }

    // MARK: - The previews of a group

    /// The tiles of a group are a fixed size and the row shows as many as fit. If the width they
    /// are offered is wider than the one they get, the stack view takes the difference off the last
    /// tile, which then draws narrower than the rest.
    func testTheTilesOfAGroupKeepTheirSize() throws {
        for cellWidth in [320.0, 375.0, 393.0, 402.0, 440.0] {
            for isOwnMessage in [true, false] {
                let available = self.calculatedBodyWidth(forCellWidth: cellWidth, isOwnMessage: isOwnMessage)
                let tileCount = GroupedFilePreviewView.tileCount(forAvailableWidth: available)
                let tileRowWidth = CGFloat(tileCount) * GroupedFilePreviewView.tileSize
                    + CGFloat(tileCount - 1) * GroupedFilePreviewView.contentSpacing

                XCTAssertLessThanOrEqual(tileRowWidth, available + 0.5,
                                         "At \(cellWidth), own: \(isOwnMessage): \(tileCount) tiles need \(tileRowWidth) but only \(available) is available")
            }
        }
    }
}
