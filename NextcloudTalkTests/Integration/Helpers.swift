//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
import Foundation
@testable import NextcloudTalk

extension XCTestCase {

    // TODO: This should probably be part of APIController
    func getRoomDict(from rawRoomDict: [Any], for account: TalkAccount) -> [NCRoom] {
        var rooms: [NCRoom] = []
        for roomDict in rawRoomDict {
            if let roomDict = roomDict as? [AnyHashable: Any], let ncRooms = NCRoom(dictionary: roomDict, andAccountId: account.accountId) {
                rooms.append(ncRooms)
            }
        }

        return rooms
    }

    func checkRoomExists(roomName: String, withAccount account: TalkAccount, completion: ((NCRoom?) -> Void)? = nil) {
        NCAPIController.sharedInstance().getRooms(forAccount: account, updateStatus: false, modifiedSince: 0) { roomsDict, error in
            XCTAssertNil(error)

            let rooms = self.getRoomDict(from: roomsDict!, for: account)
            let room = rooms.first(where: { $0.displayName == roomName })
            XCTAssertNotNil(room)

            completion?(room)
        }
    }

    func checkRoomNotExists(roomName: String, withAccount account: TalkAccount, completion: (() -> Void)? = nil) {
        NCAPIController.sharedInstance().getRooms(forAccount: account, updateStatus: false, modifiedSince: 0) { roomsDict, error in
            XCTAssertNil(error)

            let rooms = self.getRoomDict(from: roomsDict!, for: account)
            let room = rooms.first(where: { $0.displayName == roomName })
            XCTAssertNil(room)

            completion?()
        }
    }
}
