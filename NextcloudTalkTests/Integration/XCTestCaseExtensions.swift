//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Testing
@testable import NextcloudTalk

enum TestCaseError: Error {
    case expectedValueNotFound
}

extension TestBase {

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
            #expect(error == nil)

            let rooms = self.getRoomDict(from: roomsDict!, for: account)
            let room = rooms.first(where: { $0.displayName == roomName })
            #expect(room != nil)

            completion?(room)
        }
    }

    func checkRoomNotExists(roomName: String, withAccount account: TalkAccount, completion: (() -> Void)? = nil) {
        NCAPIController.sharedInstance().getRooms(forAccount: account, updateStatus: false, modifiedSince: 0) { roomsDict, error in
            #expect(error == nil)

            let rooms = self.getRoomDict(from: roomsDict!, for: account)
            let room = rooms.first(where: { $0.displayName == roomName })
            #expect(room == nil)

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

                #expect(roomName == room?.displayName)
                continuation.resume(returning: room!)
            }
        }
    }

    func joinRoom(withToken token: String, withAccount account: TalkAccount) async throws -> NCRoomController {
        let joinTracker = EventTracker()
        let observer = NotificationCenter.default.addObserver(forName: .NCRoomsManagerDidJoinRoom, object: nil, queue: nil) { notification in
            #expect(notification.userInfo?["error"] == nil)
            #expect(notification.userInfo?["statusCode"] == nil)
            #expect(notification.userInfo?["errorReason"] == nil)

            #expect(notification.userInfo?[stringForKey: "token"] == token)

            joinTracker.signal()
        }

        NCRoomsManager.shared.joinRoom(token, forAccountId: account.accountId, forCall: false)
        let joined = await wait(timeout: TestConstants.timeoutShort) { joinTracker.fired }
        NotificationCenter.default.removeObserver(observer)
        #expect(joined)

        return try #require(NCRoomsManager.shared.activeRooms[token])
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
                            #expect(chatMessage.token == token)
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
        _ = try #require(NCDatabaseManager.sharedInstance().serverCapabilities(), "Capabilities are missing")

        if !NCDatabaseManager.sharedInstance().serverHasTalkCapability(capability) {
            try Test.cancel("Capability \(capability) not available -> skipping")
        }
    }
}
