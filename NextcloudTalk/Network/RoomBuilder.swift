//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class RoomBuilder: NSObject {

    var roomParameters: [String: Any] = [:]

    @discardableResult
    func roomType(_ roomType: NCRoomType) -> Self {
        roomParameters["roomType"] = roomType.rawValue
        return self
    }

    @discardableResult
    func roomName(_ roomName: String) -> Self {
        roomParameters["roomName"] = roomName
        return self
    }

    @discardableResult
    func objecType(_ objectType: String) -> Self {
        roomParameters["objectType"] = objectType
        return self
    }

    @discardableResult
    func objectId(_ objectId: String) -> Self {
        roomParameters["objectId"] = objectId
        return self
    }

    @discardableResult
    func password(_ password: String) -> Self {
        roomParameters["password"] = password
        return self
    }

    @discardableResult
    func readOnly(_ readOnly: NCRoomReadOnlyState) -> Self {
        roomParameters["readOnly"] = readOnly.rawValue
        return self
    }

    @discardableResult
    func listable(_ listable: NCRoomListableScope) -> Self {
        roomParameters["listable"] = listable.rawValue
        return self
    }

    @discardableResult
    func messageExpiration(_ messageExpiration: Int) -> Self {
        roomParameters["messageExpiration"] = messageExpiration
        return self
    }

    @discardableResult
    func lobbyState(_ lobbyState: NCRoomLobbyState) -> Self {
        roomParameters["lobbyState"] = lobbyState.rawValue
        return self
    }

    @discardableResult
    func lobbyTimer(_ lobbyTimer: Int) -> Self {
        roomParameters["lobbyTimer"] = lobbyTimer
        return self
    }

    @discardableResult
    func sipEnabled(_ sipEnabled: Bool) -> Self {
        roomParameters["sipEnabled"] = sipEnabled
        return self
    }

    @discardableResult
    func permissions(_ permissions: [NCPermission]) -> Self {
        roomParameters["permissions"] = permissions
        return self
    }

    @discardableResult
    func reconrdingConsent(_ consent: Bool) -> Self {
        roomParameters["recordingConsent"] = consent
        return self
    }

    @discardableResult
    func mentionPermissions(_ mentionPermissions: Bool) -> Self {
        roomParameters["mentionPermissions"] = mentionPermissions
        return self
    }

    @discardableResult
    func description(_ description: String) -> Self {
        roomParameters["description"] = description
        return self
    }

    @discardableResult
    func emoji(_ emoji: String) -> Self {
        roomParameters["emoji"] = emoji
        return self
    }

    @discardableResult
    func avatarColor(_ avatarColor: String) -> Self {
        roomParameters["avatarColor"] = avatarColor
        return self
    }

    @discardableResult
    func participants(_ participants: [NCUser]) -> Self {
        if participants.isEmpty {
            return self
        }

        var participantsValue: [String: [String]] = [:]
        for participant in participants {
            participantsValue[String(participant.source), default: []].append(participant.userId)
        }

        roomParameters["participants"] = participantsValue
        return self
    }
}
