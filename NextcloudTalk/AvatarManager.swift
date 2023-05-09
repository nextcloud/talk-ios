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

@objcMembers class AvatarManager: NSObject {

    public static let shared = AvatarManager()

    // MARK: - Conversation avatars

    public func getAvatar(for room: NCRoom, with style: UIUserInterfaceStyle, completionBlock: @escaping (_ image: UIImage?) -> Void) -> SDWebImageCombinedOperation? {
        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityConversationAvatars, forAccountId: room.accountId) {
            // Server supports conversation avatars -> try to get the avatar using this API

            return NCAPIController.sharedInstance().getAvatarFor(room, with: style) { image, _ in
                completionBlock(image)
            }
        } else {
            // Server does not support conversation avatars -> use the legacy way to obtain an avatar
            return self.getFallbackAvatar(for: room, with: style, completionBlock: completionBlock)
        }
    }

    public func getGroupAvatar(with style: UIUserInterfaceStyle) -> UIImage? {
        let traitCollection = UITraitCollection(userInterfaceStyle: style)
        return UIImage(named: "group-avatar", in: nil, compatibleWith: traitCollection)
    }

    private func getFallbackAvatar(for room: NCRoom,
                                   with style: UIUserInterfaceStyle,
                                   completionBlock: @escaping (_ image: UIImage?) -> Void) -> SDWebImageCombinedOperation? {

        let traitCollection = UITraitCollection(userInterfaceStyle: style)

        if room.objectType == NCRoomObjectTypeFile {
            completionBlock(UIImage(named: "file-avatar", in: nil, compatibleWith: traitCollection))
        } else if room.objectType == NCRoomObjectTypeSharePassword {
            completionBlock(UIImage(named: "password-avatar", in: nil, compatibleWith: traitCollection))
        } else {
            switch room.type {
            case kNCRoomTypeOneToOne:
                let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: room.accountId)
                return self.getUserAvatar(for: room.name, with: style, using: account, completionBlock: completionBlock)
            case kNCRoomTypeFormerOneToOne:
                completionBlock(UIImage(named: "user-avatar", in: nil, compatibleWith: traitCollection))
            case kNCRoomTypePublic:
                completionBlock(UIImage(named: "public-avatar", in: nil, compatibleWith: traitCollection))
            case kNCRoomTypeGroup:
                completionBlock(UIImage(named: "group-avatar", in: nil, compatibleWith: traitCollection))
            case kNCRoomTypeChangelog:
                completionBlock(UIImage(named: "changelog-avatar", in: nil, compatibleWith: traitCollection))
            default:
                completionBlock(nil)
            }
        }

        return nil
    }

    // MARK: - User avatars

    public func getUserAvatar(for user: String, with style: UIUserInterfaceStyle, using account: TalkAccount?, completionBlock: @escaping (_ image: UIImage?) -> Void) -> SDWebImageCombinedOperation? {
        let account = account ?? NCDatabaseManager.sharedInstance().activeAccount()

        return NCAPIController.sharedInstance().getUserAvatar(forUser: user, using: account, with: style) { image, _ in
            if image != nil {
                completionBlock(image)
            } else {
                NSLog("Unable to get avatar for user %@", user)

                let traitCollection = UITraitCollection(userInterfaceStyle: style)
                completionBlock(UIImage(named: "user-avatar", in: nil, compatibleWith: traitCollection))
            }
        }
    }

    // MARK: - Utils

    public func createRenderedImage(image: UIImage) -> UIImage? {
        return self.createRenderedImage(image: image, width: 120, height: 120)
    }

    private func createRenderedImage(image: UIImage, width: Int, height: Int) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(.init(width: width, height: height), false, 0.0)
        image.draw(in: .init(x: 0, y: 0, width: width, height: height))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage
    }

}
