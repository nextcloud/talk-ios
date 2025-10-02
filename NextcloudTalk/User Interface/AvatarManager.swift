//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import SDWebImage

@objcMembers class AvatarManager: NSObject {

    public static let shared = AvatarManager()

    private let avatarDefaultSize = CGRect(x: 0, y: 0, width: 32, height: 32)

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

    public func getTeamAvatar(with style: UIUserInterfaceStyle) -> UIImage? {
        let traitCollection = UITraitCollection(userInterfaceStyle: style)
        return UIImage(named: "team-avatar", in: nil, compatibleWith: traitCollection)
    }

    public func getMailAvatar(with style: UIUserInterfaceStyle) -> UIImage? {
        let traitCollection = UITraitCollection(userInterfaceStyle: style)
        return UIImage(named: "mail-avatar", in: nil, compatibleWith: traitCollection)
    }

    public func getThreadAvatar(for thread: NCThread, with style: UIUserInterfaceStyle) -> UIImage? {
        let traitCollection = UITraitCollection(userInterfaceStyle: style)
        let symbolName = "bubble.left.and.bubble.right"
        let symbolColor = ColorGenerator.shared.usernameToColor(thread.title)
        let pointSize: CGFloat = 40
        let backgroundSize = CGSize(width: 100, height: 100)
        let baseBackgroundColor: UIColor = (style == .dark) ? .black : .white
        let overlayBackgroundColor = symbolColor.withAlphaComponent(0.20)

        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        guard let baseSymbol = UIImage(systemName: symbolName, compatibleWith: traitCollection)?
                .withConfiguration(config) else {
            return nil
        }

        let symbol = baseSymbol.withTintColor(symbolColor, renderingMode: .alwaysOriginal)

        let renderer = UIGraphicsImageRenderer(size: backgroundSize)
        let image = renderer.image { _ in
            let rect = CGRect(origin: .zero, size: backgroundSize)

            // Base background
            baseBackgroundColor.setFill()
            UIRectFill(rect)

            // Overlay background (with alpha component)
            overlayBackgroundColor.setFill()
            UIRectFillUsingBlendMode(rect, .normal)

            // Place symbol centered
            let symbolRect = CGRect(
                x: (backgroundSize.width - symbol.size.width) / 2,
                y: (backgroundSize.height - symbol.size.height) / 2,
                width: symbol.size.width,
                height: symbol.size.height
            )
            symbol.draw(in: symbolRect)
        }

        return image
    }

    private func getFallbackAvatar(for room: NCRoom,
                                   with style: UIUserInterfaceStyle,
                                   completionBlock: @escaping (_ image: UIImage?) -> Void) -> SDWebImageCombinedOperation? {

        let traitCollection = UITraitCollection(userInterfaceStyle: style)

        if room.objectType == NCRoomObjectTypeFile {
            completionBlock(UIImage(named: "file-avatar", in: nil, compatibleWith: traitCollection))
        } else if room.objectType == NCRoomObjectTypeSharePassword {
            completionBlock(UIImage(named: "password-avatar", in: nil, compatibleWith: traitCollection))
        } else if room.objectType == NCRoomObjectTypeEvent {
            completionBlock(UIImage(named: "event-avatar", in: nil, compatibleWith: traitCollection))
        } else {
            switch room.type {
            case .oneToOne:
                guard let account = room.account else { return nil }
                return self.getUserAvatar(forId: room.name, withStyle: style, usingAccount: account, completionBlock: completionBlock)
            case .formerOneToOne:
                completionBlock(UIImage(named: "user-avatar", in: nil, compatibleWith: traitCollection))
            case .public:
                completionBlock(UIImage(named: "public-avatar", in: nil, compatibleWith: traitCollection))
            case .group:
                completionBlock(UIImage(named: "group-avatar", in: nil, compatibleWith: traitCollection))
            case .changelog:
                completionBlock(UIImage(named: "changelog-avatar", in: nil, compatibleWith: traitCollection))
            default:
                completionBlock(nil)
            }
        }

        return nil
    }

    // MARK: - Actor avatars

    // swiftlint:disable:next function_parameter_count
    @discardableResult
    public func getActorAvatar(forId actorId: String?, withType actorType: String?, withDisplayName actorDisplayName: String?, withRoomToken roomToken: String?, withStyle style: UIUserInterfaceStyle, usingAccount account: TalkAccount, completionBlock: @escaping (_ image: UIImage?) -> Void) -> SDWebImageCombinedOperation? {
        if let actorId {
            if actorType == "bots" {
                return getBotsAvatar(forId: actorId, withStyle: style, completionBlock: completionBlock)
            } else if actorType == "users" {
                return getUserAvatar(forId: actorId, withStyle: style, usingAccount: account, completionBlock: completionBlock)
            } else if actorType == "federated_users" {
                return getFederatedUserAvatar(forId: actorId, withRoomToken: roomToken, withStyle: style, usingAccount: account, completionBlock: completionBlock)
            }
        }

        var image: UIImage?

        if actorType == AttendeeType.email.rawValue || actorType == AttendeeType.guest.rawValue {
            image = self.getGuestsAvatar(withDisplayName: actorDisplayName ?? "", withStyle: style)
        } else if actorType == AttendeeType.group.rawValue {
            image = self.getGroupAvatar(with: style)
        } else if actorType == AttendeeType.circle.rawValue || actorType == AttendeeType.teams.rawValue {
            image = self.getTeamAvatar(with: style)
        } else if actorType == "deleted_users" {
            image = self.getDeletedUserAvatar()
        } else {
            image = NCUtils.getImage(withString: "?", withBackgroundColor: .systemGray3, withBounds: self.avatarDefaultSize, isCircular: true)
        }

        completionBlock(image)
        return nil
    }

    private func getBotsAvatar(forId actorId: String, withStyle style: UIUserInterfaceStyle, completionBlock: @escaping (_ image: UIImage?) -> Void) -> SDWebImageCombinedOperation? {
        if actorId == "changelog" || actorId == "sample" {
            let traitCollection = UITraitCollection(userInterfaceStyle: style)
            completionBlock(UIImage(named: "changelog-avatar", in: nil, compatibleWith: traitCollection))
        } else {
            let image = NCUtils.getImage(withString: ">", withBackgroundColor: .systemGray3, withBounds: self.avatarDefaultSize, isCircular: true)
            completionBlock(image)
        }

        return nil
    }

    private func getGuestsAvatar(withDisplayName actorDisplayName: String, withStyle style: UIUserInterfaceStyle) -> UIImage? {
        if actorDisplayName.isEmpty {
            let traitCollection = UITraitCollection(userInterfaceStyle: style)
            return UIImage(named: "user-avatar", in: nil, compatibleWith: traitCollection)
        }

        return NCUtils.getImage(withString: actorDisplayName, withBackgroundColor: .systemGray3, withBounds: self.avatarDefaultSize, isCircular: true)
    }

    private func getDeletedUserAvatar() -> UIImage? {
        return NCUtils.getImage(withString: "X", withBackgroundColor: .systemGray3, withBounds: self.avatarDefaultSize, isCircular: true)
    }

    private func getUserAvatar(forId actorId: String, withStyle style: UIUserInterfaceStyle, usingAccount account: TalkAccount, completionBlock: @escaping (_ image: UIImage?) -> Void) -> SDWebImageCombinedOperation? {
        return NCAPIController.sharedInstance().getUserAvatar(forUser: actorId, using: account, with: style) { image, _ in
            if image != nil {
                completionBlock(image)
            } else {
                NSLog("Unable to get avatar for user %@", actorId)

                let traitCollection = UITraitCollection(userInterfaceStyle: style)
                completionBlock(UIImage(named: "user-avatar", in: nil, compatibleWith: traitCollection))
            }
        }
    }

    private func getFederatedUserAvatar(forId actorId: String, withRoomToken roomToken: String?, withStyle style: UIUserInterfaceStyle, usingAccount account: TalkAccount, completionBlock: @escaping (_ image: UIImage?) -> Void) -> SDWebImageCombinedOperation? {
        return NCAPIController.sharedInstance().getFederatedUserAvatar(forUser: actorId, inRoom: roomToken, using: account, with: style) { image, _ in
            if image != nil {
                completionBlock(image)
            } else {
                NSLog("Unable to get federated avatar for user %@", actorId)

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
