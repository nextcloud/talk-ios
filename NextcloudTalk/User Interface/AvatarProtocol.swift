//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

protocol AvatarProtocol {

    func cancelCurrentRequest()

    // MARK: - Conversation avatars
    func setAvatar(for room: NCRoom)
    func setGroupAvatar()

    // MARK: - User avatars
    func setActorAvatar(forMessage message: NCChatMessage, withAccount account: TalkAccount)
    func setActorAvatar(forId actorId: String?, withType actorType: String?, withDisplayName actorDisplayName: String?, withRoomToken roomToken: String?, using account: TalkAccount)

}
