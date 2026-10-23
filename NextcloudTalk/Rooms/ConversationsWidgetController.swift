//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import WidgetKit

// Keeps the data shown by the conversations widgets up to date.
// All methods are expected to be called on the main thread.
class ConversationsWidgetController {

    static let shared = ConversationsWidgetController()

    private static let avatarSize = CGSize(width: 96, height: 96)

    private var pendingAvatarRequests = 0

    func startObserving() {
        let notificationNames: [Notification.Name] = [
            .NCRoomsManagerDidUpdateRooms,
            .NCSettingsControllerDidChangeActiveAccount,
            UIApplication.didEnterBackgroundNotification
        ]

        for notificationName in notificationNames {
            NotificationCenter.default.addObserver(forName: notificationName, object: nil, queue: .main) { [weak self] _ in
                self?.updateSnapshot()
            }
        }
    }

    func updateSnapshot() {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else { return }

        let databaseManager = NCDatabaseManager.sharedInstance()
        let accounts = databaseManager.allAccounts().map { account in
            Self.snapshotAccount(for: account, rooms: databaseManager.roomsForAccountId(account.accountId, withRealm: nil))
        }

        let activeAccountId = accounts.isEmpty ? nil : databaseManager.activeAccount().accountId
        let snapshot = ConversationsSnapshot(appName: talkAppName,
                                             themeColor: Self.snapshotColor(for: NCAppBranding.themeColor()),
                                             activeAccountId: activeAccountId,
                                             accounts: accounts)

        do {
            if try snapshot.write(to: containerURL) {
                WidgetCenter.shared.reloadTimelines(ofKind: ConversationsSnapshot.widgetKind)
            }
        } catch {
            NCLog.log("Failed to store the conversations widget data: \(error.localizedDescription)")
        }

        self.updateAvatars(for: snapshot, in: containerURL)
    }

    // MARK: - Avatars

    private func updateAvatars(for snapshot: ConversationsSnapshot, in containerURL: URL) {
        let avatarFolderURL = ConversationsSnapshot.avatarFolderURL(in: containerURL)
        try? FileManager.default.createDirectory(at: avatarFolderURL, withIntermediateDirectories: true)

        var avatarFileNames = Set<String>()

        for account in snapshot.accounts {
            for conversation in account.conversations {
                avatarFileNames.insert(conversation.avatarFileName)

                let avatarURL = avatarFolderURL.appendingPathComponent(conversation.avatarFileName)
                guard !FileManager.default.fileExists(atPath: avatarURL.path),
                      let room = NCDatabaseManager.sharedInstance().room(withToken: conversation.id, forAccountId: account.id)
                else { continue }

                self.pendingAvatarRequests += 1

                _ = AvatarManager.shared.getAvatar(for: room, with: .light) { [weak self] image in
                    if let image {
                        Self.storeAvatar(image, at: avatarURL)
                    }

                    DispatchQueue.main.async {
                        self?.avatarRequestFinished()
                    }
                }
            }
        }

        // Remove the avatars of conversations that are no longer shown
        let storedFileNames = (try? FileManager.default.contentsOfDirectory(atPath: avatarFolderURL.path)) ?? []
        for fileName in storedFileNames where !avatarFileNames.contains(fileName) {
            try? FileManager.default.removeItem(at: avatarFolderURL.appendingPathComponent(fileName))
        }
    }

    private func avatarRequestFinished() {
        self.pendingAvatarRequests -= 1

        if self.pendingAvatarRequests == 0 {
            WidgetCenter.shared.reloadTimelines(ofKind: ConversationsSnapshot.widgetKind)
        }
    }

    private static func storeAvatar(_ image: UIImage, at avatarURL: URL) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderedImage = UIGraphicsImageRenderer(size: avatarSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: avatarSize))
        }

        try? renderedImage.pngData()?.write(to: avatarURL, options: .atomic)
    }

    // MARK: - Snapshot

    static func snapshotAccount(for account: TalkAccount, rooms: [NCRoom]) -> ConversationsSnapshot.Account {
        let visibleRooms = rooms.filter { !$0.isArchived }
        let conversations = visibleRooms.prefix(ConversationsSnapshot.maxConversationsPerAccount).map { snapshotConversation(for: $0, account: account) }

        var displayName = account.userDisplayName
        if let host = URL(string: account.server)?.host {
            displayName += " (\(host))"
        }

        return ConversationsSnapshot.Account(id: account.accountId,
                                             displayName: displayName,
                                             unreadConversationCount: visibleRooms.filter { $0.unreadMessages > 0 }.count,
                                             conversations: Array(conversations))
    }

    static func snapshotConversation(for room: NCRoom, account: TalkAccount) -> ConversationsSnapshot.Conversation {
        return ConversationsSnapshot.Conversation(id: room.token,
                                                  displayName: room.displayName,
                                                  lastMessage: room.isSensitive ? nil : room.lastMessageString?.string,
                                                  lastActivity: room.lastActivity > 0 ? Date(timeIntervalSince1970: TimeInterval(room.lastActivity)) : nil,
                                                  unreadMessages: room.unreadMessages,
                                                  hasUnreadMention: room.hasUnreadMention,
                                                  hasCall: room.hasCall,
                                                  avatarFileName: ConversationsSnapshot.avatarFileName(forAccountId: account.accountId, roomToken: room.token),
                                                  url: openConversationURL(for: room, account: account))
    }

    static func openConversationURL(for room: NCRoom, account: TalkAccount) -> URL? {
        var components = URLComponents()
        components.scheme = "nextcloudtalk"
        components.host = "open-conversation"
        components.queryItems = [
            URLQueryItem(name: "server", value: account.server),
            URLQueryItem(name: "user", value: account.userId),
            URLQueryItem(name: "withRoomToken", value: room.token)
        ]

        return components.url
    }

    static func snapshotColor(for color: UIColor) -> ConversationsSnapshot.Color {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: nil)

        return ConversationsSnapshot.Color(red: Double(red), green: Double(green), blue: Double(blue))
    }
}
