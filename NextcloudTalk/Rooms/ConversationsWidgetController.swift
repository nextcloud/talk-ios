//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import WidgetKit

// Keeps the data of the home and lock screen widgets up to date, see ConversationsWidgetData
class ConversationsWidgetController {

    public static let shared = ConversationsWidgetController()

    // Enough for the large widget, the smaller ones show less
    private let maxConversations = 6
    private let avatarSize = CGSize(width: 88, height: 88)

    private var lastSavedData: ConversationsWidgetData?
    private var pendingUpdate: DispatchWorkItem?
    private var avatarsBeingLoaded = Set<String>()

    func start() {
        NotificationCenter.default.addObserver(self, selector: #selector(setNeedsUpdate), name: .NCRoomsManagerDidUpdateRooms, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setNeedsUpdate), name: .NCSettingsControllerDidChangeActiveAccount, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(activeAccountDidChange), name: .NCSettingsControllerDidChangeActiveAccount, object: nil)

        self.setNeedsUpdate()
    }

    // The status of the new account is only known once it was loaded again
    @objc private func activeAccountDidChange() {
        DispatchQueue.main.async {
            TalkWidgetActions.userStatusDidChange(nil)
        }
    }

    // Rooms are often updated several times in a row, so the update is slightly delayed to only do it once
    @objc func setNeedsUpdate() {
        DispatchQueue.main.async {
            self.pendingUpdate?.cancel()

            let update = DispatchWorkItem {
                self.update()
            }

            self.pendingUpdate = update
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: update)
        }
    }

    private func update() {
        guard NCDatabaseManager.sharedInstance().numberOfAccounts() > 0 else {
            self.removeData()
            return
        }

        let account = NCDatabaseManager.sharedInstance().activeAccount()
        let rooms = NCDatabaseManager.sharedInstance().roomsForAccountId(account.accountId, withRealm: nil).filter { !$0.isArchived }

        // Favorites first, the remaining space is filled with the most recent conversations
        let byLastActivity: (NCRoom, NCRoom) -> Bool = { $0.lastActivity > $1.lastActivity }
        let favoriteRooms = rooms.filter(\.isFavorite).sorted(by: byLastActivity)
        let otherRooms = rooms.filter { !$0.isFavorite }.sorted(by: byLastActivity)
        let shownRooms = Array((favoriteRooms + otherRooms).prefix(maxConversations))

        let avatarsDirectoryURL = ConversationsWidgetData.avatarsDirectoryURL(appGroupIdentifier: groupIdentifier)

        let conversations = shownRooms.map { room in
            let avatarFileName = self.avatarFileName(for: room)
            let avatarExists = avatarsDirectoryURL.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent(avatarFileName).path) } ?? false

            return ConversationsWidgetData.Conversation(id: room.internalId,
                                                        token: room.token,
                                                        displayName: room.displayName,
                                                        unreadMessages: room.unreadMessages,
                                                        unreadMention: room.unreadMention,
                                                        isFavorite: room.isFavorite,
                                                        hasCall: room.hasCall,
                                                        avatarFileName: avatarExists ? avatarFileName : nil)
        }

        let data = ConversationsWidgetData(server: account.server,
                                           userId: account.userId,
                                           conversations: conversations,
                                           unreadConversations: rooms.filter { $0.unreadMessages > 0 }.count,
                                           unreadMentions: rooms.filter(\.unreadMention).count)

        self.removeUnusedAvatars(keeping: Set(shownRooms.map { self.avatarFileName(for: $0) }))
        self.loadMissingAvatars(for: shownRooms)

        guard data != lastSavedData else { return }

        do {
            try data.save(appGroupIdentifier: groupIdentifier)
            self.lastSavedData = data
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            NCLog.log("Could not save widget data: \(error.localizedDescription)")
        }
    }

    private func removeData() {
        guard lastSavedData != nil || ConversationsWidgetData.load(appGroupIdentifier: groupIdentifier) != nil else { return }

        ConversationsWidgetData.remove(appGroupIdentifier: groupIdentifier)
        self.lastSavedData = nil
        WidgetCenter.shared.reloadAllTimelines()

        DispatchQueue.main.async {
            TalkWidgetActions.accountsDidChange()
        }
    }

    // MARK: - Avatars

    private func avatarFileName(for room: NCRoom) -> String {
        // The version changes with the avatar, so a changed avatar is stored as a new file
        let name = "\(room.internalId)-\(room.avatarVersion ?? "")"
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let fileName = String(name.unicodeScalars.map { allowedCharacters.contains($0) ? Character($0) : "_" })

        return "\(fileName).png"
    }

    private func loadMissingAvatars(for rooms: [NCRoom]) {
        guard let avatarsDirectoryURL = ConversationsWidgetData.avatarsDirectoryURL(appGroupIdentifier: groupIdentifier) else { return }

        for room in rooms {
            let fileName = self.avatarFileName(for: room)
            let fileURL = avatarsDirectoryURL.appendingPathComponent(fileName)

            guard !FileManager.default.fileExists(atPath: fileURL.path), !avatarsBeingLoaded.contains(fileName) else { continue }

            avatarsBeingLoaded.insert(fileName)

            _ = AvatarManager.shared.getAvatar(for: room, with: .light) { [weak self] image in
                DispatchQueue.main.async {
                    guard let self else { return }

                    self.avatarsBeingLoaded.remove(fileName)

                    guard let image, let pngData = self.resizedAvatar(image).pngData() else { return }

                    do {
                        try FileManager.default.createDirectory(at: avatarsDirectoryURL, withIntermediateDirectories: true)
                        try pngData.write(to: fileURL, options: [.atomic, .noFileProtection])
                        self.setNeedsUpdate()
                    } catch {
                        NCLog.log("Could not save widget avatar: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func resizedAvatar(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        return UIGraphicsImageRenderer(size: avatarSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: avatarSize))
        }
    }

    private func removeUnusedAvatars(keeping fileNames: Set<String>) {
        guard let avatarsDirectoryURL = ConversationsWidgetData.avatarsDirectoryURL(appGroupIdentifier: groupIdentifier),
              let storedFileNames = try? FileManager.default.contentsOfDirectory(atPath: avatarsDirectoryURL.path)
        else { return }

        for storedFileName in storedFileNames where !fileNames.contains(storedFileName) {
            try? FileManager.default.removeItem(at: avatarsDirectoryURL.appendingPathComponent(storedFileName))
        }
    }
}
