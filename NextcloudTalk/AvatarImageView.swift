//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import SDWebImage

@objcMembers class AvatarImageView: UIImageView {

    private var currentRequest: SDWebImageCombinedOperation?

    public func cancelCurrentRequest() {
        self.currentRequest?.cancel()
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.commonInit()
    }

    private func commonInit() {
        self.contentMode = .scaleToFill
    }

    // MARK: - Conversation avatars

    public func setAvatar(for room: NCRoom) {
        self.cancelCurrentRequest()

        self.currentRequest = AvatarManager.shared.getAvatar(for: room, with: self.traitCollection.userInterfaceStyle) { image in
            guard let image = image else {
                return
            }

            self.image = image
            self.contentMode = .scaleToFill
            self.backgroundColor = .clear
        }
    }

    public func setGroupAvatar() {
        if let image = AvatarManager.shared.getGroupAvatar(with: self.traitCollection.userInterfaceStyle) {
            self.image = image
        }
    }

    public func setMailAvatar() {
        if let image = AvatarManager.shared.getMailAvatar(with: self.traitCollection.userInterfaceStyle) {
            self.image = image
        }
    }

    // MARK: - User avatars

    public func setActorAvatar(forMessage message: NCChatMessage) {
        guard let account = message.account else { return }
        self.setActorAvatar(forId: message.actorId, withType: message.actorType, withDisplayName: message.actorDisplayName, withRoomToken: message.token, using: account)
    }

    public func setActorAvatar(forId actorId: String?, withType actorType: String?, withDisplayName actorDisplayName: String?, withRoomToken roomToken: String?, using account: TalkAccount) {
        self.cancelCurrentRequest()

        self.currentRequest = AvatarManager.shared.getActorAvatar(forId: actorId, withType: actorType, withDisplayName: actorDisplayName, withRoomToken: roomToken, withStyle: self.traitCollection.userInterfaceStyle, usingAccount: account) { image in
            guard let image = image else {
                return
            }

            self.image = image
            self.contentMode = .scaleToFill
        }
    }
}
