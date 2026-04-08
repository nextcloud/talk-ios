//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
import Foundation
@testable import NextcloudTalk

enum TestCaseError: Error {
    case expectedValueNotFound
}

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

    func createUniqueRoom(prefix: String, withAccount account: TalkAccount) async throws -> NCRoom {
        let roomName = "\(prefix)-\(UUID().uuidString)"

        return try await withCheckedThrowingContinuation { continuation in
            NCAPIController.sharedInstance().createRoom(forAccount: account, withInvite: nil, ofType: .public, andName: roomName) { room, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                XCTAssertEqual(roomName, room?.displayName)
                continuation.resume(returning: room!)
            }
        }
    }

    func joinRoom(withToken token: String, withAccount account: TalkAccount) async throws -> NCRoomController {
        let exp = expectation(forNotification: .NCRoomsManagerDidJoinRoom, object: nil) { notification -> Bool in
            XCTAssertNil(notification.userInfo?["error"])
            XCTAssertNil(notification.userInfo?["statusCode"])
            XCTAssertNil(notification.userInfo?["errorReason"])

            XCTAssertEqual(notification.userInfo?[stringForKey: "token"], token)

            return true
        }

        NCRoomsManager.shared.joinRoom(token, forCall: false)
        await fulfillment(of: [exp], timeout: TestConstants.timeoutShort)

        return try XCTUnwrap(NCRoomsManager.shared.activeRooms[token])
    }

    struct ReceiveMessageDetails {
        var lastKnownMessage: Int
        var lastCommonReadMessage: Int
        var statusCode: Int
    }

    @discardableResult
    func sendMessage(message: String, inRoom token: String, withAccount account: TalkAccount) async throws -> (message: NCChatMessage, details: ReceiveMessageDetails) {
        return try await withCheckedThrowingContinuation { continuation in
            NCAPIController.sharedInstance().sendChatMessage(message, toRoom: token, threadTitle: "", replyTo: 0, referenceId: "", silently: false, forAccount: account) { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                NCAPIController.sharedInstance().receiveChatMessages(ofRoom: token,
                                                                     fromLastMessageId: 0,
                                                                     inThread: 0,
                                                                     history: false,
                                                                     includeLastMessage: true,
                                                                     timeout: false,
                                                                     limit: 0,
                                                                     lastCommonReadMessage: 0,
                                                                     setReadMarker: false,
                                                                     markNotificationsAsRead: false,
                                                                     forAccount: account) { messages, lastKnownMessage, lastCommonReadMessage, error, statusCode in

                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    for dictMessage in messages! {
                        let chatMessage = NCChatMessage(dictionary: dictMessage, andAccountId: account.accountId)!

                        if chatMessage.message == message {
                            XCTAssertEqual(chatMessage.token, token)
                            let details = ReceiveMessageDetails(lastKnownMessage: lastKnownMessage, lastCommonReadMessage: lastCommonReadMessage, statusCode: statusCode)
                            continuation.resume(returning: (chatMessage, details))

                            return
                        }
                    }

                    continuation.resume(throwing: TestCaseError.expectedValueNotFound)
                }
            }
        }
    }

    func skipWithoutCapability(capability: String) throws {
        let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities()

        guard serverCapabilities != nil else {
            XCTFail("Capabilities are missing")
            return
        }

        try XCTSkipIf(!NCDatabaseManager.sharedInstance().serverHasTalkCapability(capability), "Capability \(capability) not available -> skipping")
    }
}
