//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objc public extension NCDatabaseManager {

    func increaseEmojiUsage(forEmoji emojiString: String, forAccount accountId: String) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId) else { return }
        var newData: [String: Int]?

        if let data = account.frequentlyUsedEmojisJSONString.data(using: .utf8),
           var emojiData = try? JSONSerialization.jsonObject(with: data) as? [String: Int] {

            if let currentEmojiCount = emojiData[emojiString] {
                emojiData[emojiString] = currentEmojiCount + 1
            } else {
                emojiData[emojiString] = 1
            }

            newData = emojiData
        } else {
            // No existing data, start new
            newData = [emojiString: 1]
        }

        guard let newData, let jsonData = try? JSONSerialization.data(withJSONObject: newData),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else { return }

        let realm = RLMRealm.default()

        try? realm.transaction {
            if let managedTalkAccount = TalkAccount.objects(where: "accountId = %@", account.accountId).firstObject() as? TalkAccount {
                managedTalkAccount.frequentlyUsedEmojisJSONString = jsonString
            }
        }
    }

    // MARK: - Rooms

    func roomsForAccountId(_ accountId: String, withRealm realm: RLMRealm?) -> [NCRoom] {
        let query = NSPredicate(format: "accountId = %@", accountId)
        var managedRooms: RLMResults<AnyObject>

        if let realm {
            managedRooms = NCRoom.objects(in: realm, with: query)
        } else {
            managedRooms = NCRoom.objects(with: query)
        }

        // Create an unmanaged copy of the rooms
        var unmanagedRooms: [NCRoom] = []

        for case let managedRoom as NCRoom in managedRooms {
            if managedRoom.isBreakoutRoom, managedRoom.lobbyState == .moderatorsOnly {
                continue
            }

            unmanagedRooms.append(NCRoom(value: managedRoom))
        }

        // Sort by favorites first, then by lastActivity
        unmanagedRooms.sort { first, second in
            (first.isFavorite ? 1 : 0, first.lastActivity) > (second.isFavorite ? 1 : 0, second.lastActivity)
        }

        return unmanagedRooms
    }
}
