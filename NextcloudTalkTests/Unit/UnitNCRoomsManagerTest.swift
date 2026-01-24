//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitNCRoomsManagerTest: TestBaseRealm {

    func testOfflineMessageFailure() throws {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let roomToken = "offToken"

        addRoom(withToken: roomToken)

        // Create 2 messages which are in different sections
        let oldOfflineMessage = NCChatMessage()

        oldOfflineMessage.internalId = "internal1"
        oldOfflineMessage.accountId = activeAccount.accountId
        oldOfflineMessage.actorDisplayName = activeAccount.userDisplayName
        oldOfflineMessage.actorId = activeAccount.userId
        oldOfflineMessage.actorType = "users"
        oldOfflineMessage.token = roomToken
        oldOfflineMessage.message = "Message 1"
        oldOfflineMessage.isOfflineMessage = true
        oldOfflineMessage.sendingFailed = false

        // 12h is the threshold, set it to 13 hours
        oldOfflineMessage.timestamp = Int(Date().timeIntervalSince1970) - (60 * 60 * 13)

        try? realm.transaction {
            realm.add(oldOfflineMessage)
        }

        XCTAssertEqual(NCChatMessage.allObjects().count, 1)

        let exp = expectation(description: "\(#function)\(#line)")
        expectation(forNotification: .NCChatControllerDidSendChatMessage, object: NCRoomsManager.shared)

        NCRoomsManager.shared.resendOfflineMessages(forToken: roomToken) {
            exp.fulfill()
        }

        waitForExpectations(timeout: TestConstants.timeoutShort, handler: nil)

        let realmMessage = NCChatMessage.allObjects().firstObject()!
        XCTAssertTrue(realmMessage.sendingFailed)
        XCTAssertFalse(realmMessage.isOfflineMessage)
    }

    func testUpdateRoomWithDict() throws {
        let dataJson = """
            {
                "id": 5,
                "token": "noszqmnh",
                "type": 2,
                "name": "Test2",
                "displayName": "Test2",
                "objectType": "",
                "objectId": "",
                "participantType": 1,
                "participantFlags": 0,
                "readOnly": 0,
                "hasPassword": false,
                "hasCall": false,
                "callStartTime": 0,
                "callRecording": 0,
                "canStartCall": true,
                "lastActivity": 1769032238,
                "lastReadMessage": 74,
                "unreadMessages": 0,
                "unreadMention": false,
                "unreadMentionDirect": false,
                "isFavorite": false,
                "canLeaveConversation": true,
                "canDeleteConversation": true,
                "notificationLevel": 1,
                "notificationCalls": 1,
                "lobbyState": 0,
                "lobbyTimer": 0,
                "lastPing": 0,
                "sessionId": "0",
                "sipEnabled": 0,
                "actorType": "users",
                "actorId": "admin",
                "attendeeId": 5,
                "permissions": 254,
                "attendeePermissions": 0,
                "callPermissions": 0,
                "defaultPermissions": 0,
                "canEnableSIP": false,
                "attendeePin": "",
                "description": "",
                "lastCommonReadMessage": 74,
                "listable": 0,
                "callFlag": 0,
                "messageExpiration": 0,
                "avatarVersion": "02234d2d",
                "isCustomAvatar": false,
                "breakoutRoomMode": 0,
                "breakoutRoomStatus": 0,
                "recordingConsent": 0,
                "mentionPermissions": 0,
                "liveTranscriptionLanguageId": "",
                "lastPinnedId": 0,
                "hiddenPinnedId": 0,
                "isArchived": false,
                "isImportant": false,
                "isSensitive": false,
                "hasScheduledMessages": 0,
                "lastMessage": {
                    "id": 74,
                    "token": "noszqmnh",
                    "actorType": "users",
                    "actorId": "admin",
                    "actorDisplayName": "admin",
                    "timestamp": 1769032238,
                    "message": "Hey",
                    "messageParameters": [],
                    "systemMessage": "",
                    "messageType": "comment",
                    "isReplyable": true,
                    "referenceId": "",
                    "reactions": {},
                    "expirationTimestamp": 0,
                    "markdown": true,
                    "threadId": 74
                }
            }
        """

        // swiftlint:disable:next force_cast
        let roomDict = try JSONSerialization.jsonObject(with: dataJson.data(using: .utf8)!) as! [String: Any]

        XCTAssertEqual(NCChatMessage.allObjects().count, 0)
        XCTAssertEqual(NCRoom.allObjects().count, 0)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        try realm.transaction {
            NCRoomsManager.shared.updateRoom(withDict: roomDict, withAccount: activeAccount, withTimestamp: Int(Date().timeIntervalSince1970), withRealm: realm)
        }

        XCTAssertEqual(NCChatMessage.allObjects().count, 1)
        XCTAssertEqual(NCRoom.allObjects().count, 1)

        let message = try XCTUnwrap(NCChatMessage.allObjects().firstObject() as? NCChatMessage)
        let room = try XCTUnwrap(NCRoom.allObjects().firstObject() as? NCRoom)

        XCTAssertEqual(message.message, "Hey")
        XCTAssertEqual(message.timestamp, 1769032238)

        XCTAssertEqual(room.name, "Test2")
        XCTAssertEqual(room.token, "noszqmnh")
    }

}
