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

        // Sort rooms
        let capabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: accountId)

        unmanagedRooms.sort { (first: NCRoom, second: NCRoom) in
            // 1. Favorites
            if first.isFavorite != second.isFavorite {
                return first.isFavorite
            }

            if let capabilities {
                let groupMode = NCRoomGroupMode(rawValue: capabilities.roomsGroupMode) ?? .none
                let sortOrder = NCRoomSortOrder(rawValue: capabilities.roomsSortOrder) ?? .activity

                // 2. Group mode
                if groupMode == .groupFirst || groupMode == .privateFirst {
                    let firstIsOneToOne = (first.type == .oneToOne || first.type == .formerOneToOne)
                    let secondIsOneToOne = (second.type == .oneToOne || second.type == .formerOneToOne)

                    if firstIsOneToOne != secondIsOneToOne {
                        let oneToOneFirst = groupMode == .privateFirst
                        return firstIsOneToOne == oneToOneFirst
                    }
                }

                // 3. Sort order
                if sortOrder == .alphabetical {
                    return first.displayName.localizedCaseInsensitiveCompare(second.displayName) == .orderedAscending
                }
            }

            // Default: Recent activity
            return first.lastActivity > second.lastActivity
        }

        return unmanagedRooms
    }
}
