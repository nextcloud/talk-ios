//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

/// The items of the strip at the bottom of the attachment sheet. They are the entries the "+" menu of the chat
/// had before the sheet replaced it, in the order they are shown in the strip.
enum AttachmentSheetAction: CaseIterable {
    case camera
    case photoLibrary
    case giphy
    case files
    case nextcloudFiles
    case thread
    case poll
    case location
    case contact

    /// Everything that decides which items are available. Kept apart from the database and the room, so the
    /// rules can be tested without them.
    struct Context {
        var isCameraAvailable: Bool
        var isGiphyAvailable: Bool
        var hasThreadsCapability: Bool
        var hasPollsCapability: Bool
        var hasLocationCapability: Bool
        var roomType: NCRoomType
        var isInThread: Bool
    }

    /// The items to show, in the order of the strip.
    static func availableActions(in context: Context) -> [AttachmentSheetAction] {
        var actions: [AttachmentSheetAction] = []

        if context.isCameraAvailable {
            actions.append(.camera)
        }

        actions.append(.photoLibrary)

        if context.isGiphyAvailable {
            actions.append(.giphy)
        }

        actions.append(.files)
        actions.append(.nextcloudFiles)

        // Rich objects and polls can not be shared in threads yet. Remove this check when they can.
        if !context.isInThread {
            if context.hasThreadsCapability {
                actions.append(.thread)
            }

            if context.hasPollsCapability, context.roomType != .oneToOne, context.roomType != .noteToSelf {
                actions.append(.poll)
            }

            if context.hasLocationCapability {
                actions.append(.location)
            }

            actions.append(.contact)
        }

        return actions
    }

    /// The items to show for a conversation, based on what the server and the conversation allow.
    @MainActor
    static func availableActions(room: NCRoom, account: TalkAccount, thread: NCThread?) -> [AttachmentSheetAction] {
        let databaseManager = NCDatabaseManager.sharedInstance()
        let serverCapabilities = databaseManager.serverCapabilities(forAccountId: account.accountId)

        let context = Context(isCameraAvailable: InAppCameraViewController.isCameraAvailable,
                              isGiphyAvailable: serverCapabilities?.giphyEnabled == true && serverCapabilities?.giphyConfigured == true,
                              hasThreadsCapability: databaseManager.roomHasTalkCapability(.threads, for: room),
                              hasPollsCapability: databaseManager.roomHasTalkCapability(.talkPolls, for: room),
                              hasLocationCapability: databaseManager.roomHasTalkCapability(.locationSharing, for: room),
                              roomType: room.type,
                              isInThread: thread != nil)

        return self.availableActions(in: context)
    }

    var title: String {
        switch self {
        case .camera:
            return NSLocalizedString("Camera", comment: "")
        case .photoLibrary:
            return NSLocalizedString("Photo Library", comment: "")
        case .giphy:
            // Not localized: "GIF" is a file format and "Giphy" a company name
            return "GIF (Giphy)"
        case .files:
            return NSLocalizedString("Files", comment: "")
        case .nextcloudFiles:
            return filesAppName
        case .thread:
            return NSLocalizedString("Thread", comment: "Context menu action to reply to a message in a thread")
        case .poll:
            return NSLocalizedString("Poll", comment: "")
        case .location:
            return NSLocalizedString("Location", comment: "")
        case .contact:
            return NSLocalizedString("Contacts", comment: "")
        }
    }

    var image: UIImage? {
        switch self {
        case .camera:
            return UIImage(systemName: "camera")
        case .photoLibrary:
            return UIImage(systemName: "photo")
        case .giphy:
            return UIImage(systemName: "play.square.stack")
        case .files:
            return UIImage(systemName: "doc")
        case .nextcloudFiles:
            return UIImage(named: "logo-action")?.withRenderingMode(.alwaysTemplate)
        case .thread:
            return UIImage(systemName: "bubble.left.and.bubble.right")
        case .poll:
            return UIImage(systemName: "chart.bar")
        case .location:
            return UIImage(systemName: "location")
        case .contact:
            return UIImage(systemName: "person")
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .camera: return "attachmentSheetCamera"
        case .photoLibrary: return "attachmentSheetPhotoLibrary"
        case .giphy: return "attachmentSheetGiphy"
        case .files: return "attachmentSheetFiles"
        case .nextcloudFiles: return "attachmentSheetNextcloudFiles"
        case .thread: return "attachmentSheetThread"
        case .poll: return "attachmentSheetPoll"
        case .location: return "attachmentSheetLocation"
        case .contact: return "attachmentSheetContact"
        }
    }
}
