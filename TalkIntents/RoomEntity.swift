//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AppIntents

struct RoomEntity: AppEntity {
    var id: String
    var token: String
    var displayName: String

    static var defaultQuery = RoomEntityQuery()
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Conversation"

    init(room: NCRoom) {
        id = room.internalId
        token = room.token
        displayName = room.displayName

        // Can't use async here to fetch room avatars. We could query our local cache
        // and in case of a cache hit use that image.
    }

    var displayRepresentation: DisplayRepresentation {
        return DisplayRepresentation(title: "\(displayName)")
    }
}

struct RoomEntityQuery: EntityStringQuery {
    @IntentParameterDependency<SendTalkMessageIntent>(\.$account)
    var intent

    func entities(matching string: String) async throws -> [RoomEntity] {
        guard let intent else { return [] }
        let rooms = NCDatabaseManager.sharedInstance().roomsForAccountId(intent.account.id, withRealm: nil)

        return rooms.filter({ $0.displayName.contains(string) }).map { RoomEntity(room: $0) }
    }

    func suggestedEntities() async throws -> [RoomEntity] {
        guard let intent else { return [] }
        let rooms = NCDatabaseManager.sharedInstance().roomsForAccountId(intent.account.id, withRealm: nil)

        return rooms.map { RoomEntity(room: $0) }
    }

    func entities(for identifiers: [String]) async throws -> [RoomEntity] {
        guard let intent else { return [] }
        let rooms = NCDatabaseManager.sharedInstance().roomsForAccountId(intent.account.id, withRealm: nil)

        return rooms.filter({ identifiers.contains($0.internalId) }).map { RoomEntity(room: $0) }
    }

}
