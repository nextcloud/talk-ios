//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import SDWebImage

@objcMembers class AvatarButton: UIButton, AvatarProtocol {

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
        self.layer.masksToBounds = true
        self.imageView?.contentMode = .scaleToFill
        self.imageView?.frame = self.frame
        self.contentVerticalAlignment = .fill
        self.contentHorizontalAlignment = .fill
        self.backgroundColor = .systemGray3
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.layer.cornerRadius = self.frame.width / 2.0
    }

    // MARK: - Conversation avatars

    public func setAvatar(for room: NCRoom) {
        self.cancelCurrentRequest()

        self.currentRequest = AvatarManager.shared.getAvatar(for: room, with: self.traitCollection.userInterfaceStyle) { image in
            guard let image = image else {
                return
            }

            self.setImage(image, for: .normal)
            self.backgroundColor = .clear
        }
    }

    public func setGroupAvatar() {
        if let image = AvatarManager.shared.getGroupAvatar(with: self.traitCollection.userInterfaceStyle) {
            self.setImage(image, for: .normal)
        }
    }

    // MARK: - User avatars

    public func setActorAvatar(forMessage message: NCChatMessage, withAccount account: TalkAccount) {
        self.setActorAvatar(forId: message.actorId, withType: message.actorType, withDisplayName: message.actorDisplayName, withRoomToken: message.token, using: account)
    }

    public func setActorAvatar(forId actorId: String?, withType actorType: String?, withDisplayName actorDisplayName: String?, withRoomToken roomToken: String?, using account: TalkAccount) {
        self.cancelCurrentRequest()

        self.currentRequest = AvatarManager.shared.getActorAvatar(forId: actorId, withType: actorType, withDisplayName: actorDisplayName, withRoomToken: roomToken, withStyle: self.traitCollection.userInterfaceStyle, usingAccount: account) { image in
            guard let image = image else {
                return
            }

            self.setImage(image, for: .normal)
        }
    }
}
