//
// Copyright (c) 2023 Marcel Müller <marcel.mueller@nextcloud.com>
//
// Author Marcel Müller <marcel.mueller@nextcloud.com>
//
// GNU GPL version 3 or any later version
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import UIKit
import SDWebImage

@objcMembers class AvatarButton: UIButton {

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
        }
    }

    public func setGroupAvatar() {
        if let image = AvatarManager.shared.getGroupAvatar(with: self.traitCollection.userInterfaceStyle) {
            self.setImage(image, for: .normal)
        }
    }

    // MARK: - User avatars

    public func setActorAvatar(forMessage message: NCChatMessage) {
        self.setActorAvatar(forId: message.actorId, withType: message.actorType, withDisplayName: message.actorDisplayName, withRoomToken: message.token)
    }

    public func setActorAvatar(forId actorId: String?, withType actorType: String?, withDisplayName actorDisplayName: String?, withRoomToken roomToken: String?) {
        self.setActorAvatar(forId: actorId, withType: actorType, withDisplayName: actorDisplayName, withRoomToken: roomToken, using: nil)
    }

    public func setActorAvatar(forId actorId: String?, withType actorType: String?, withDisplayName actorDisplayName: String?, withRoomToken roomToken: String?, using account: TalkAccount?) {
        self.cancelCurrentRequest()

        self.currentRequest = AvatarManager.shared.getActorAvatar(forId: actorId, withType: actorType, withDisplayName: actorDisplayName, withRoomToken: roomToken, withStyle: self.traitCollection.userInterfaceStyle, usingAccount: account) { image in
            guard let image = image else {
                return
            }

            self.setImage(image, for: .normal)
        }
    }
}
