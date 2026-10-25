//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

// What the widgets show. The app writes it into the shared app group container whenever the
// conversations change and the widgets only read it, so they need neither network access nor the database.
// This file is part of the app and of the widget extension.
struct ConversationsWidgetData: Codable, Equatable {

    struct Conversation: Codable, Equatable, Identifiable {
        // The internalId of the room
        let id: String
        let token: String
        let displayName: String
        let unreadMessages: Int
        let unreadMention: Bool
        let isFavorite: Bool
        let hasCall: Bool
        // Name of the avatar image in the avatars directory, if it was stored already
        let avatarFileName: String?
    }

    let server: String
    let userId: String
    let conversations: [Conversation]
    let unreadConversations: Int
    let unreadMentions: Int

    static let conversationsWidgetKind = "ConversationsWidget"
    static let unreadWidgetKind = "UnreadConversationsWidget"

    private static let directoryName = "Widgets"
    private static let dataFileName = "conversations.json"
    private static let avatarsDirectoryName = "Avatars"

    // Opens the conversation, same as a nextcloudtalk:// link from the web
    func openURL(for conversation: Conversation) -> URL? {
        var components = URLComponents()
        components.scheme = "nextcloudtalk"
        components.host = "open-conversation"
        components.queryItems = [
            URLQueryItem(name: "server", value: server),
            URLQueryItem(name: "user", value: userId),
            URLQueryItem(name: "withRoomToken", value: conversation.token)
        ]

        return components.url
    }

    // The same data, but with the conversation shown as read, until the app has the real state from the server
    func markingAsRead(token: String) -> ConversationsWidgetData {
        guard let conversation = conversations.first(where: { $0.token == token }), conversation.unreadMessages > 0 else { return self }

        let updatedConversations = conversations.map { conversation in
            guard conversation.token == token else { return conversation }

            return Conversation(id: conversation.id, token: conversation.token, displayName: conversation.displayName,
                                unreadMessages: 0, unreadMention: false, isFavorite: conversation.isFavorite,
                                hasCall: conversation.hasCall, avatarFileName: conversation.avatarFileName)
        }

        return ConversationsWidgetData(server: server, userId: userId, conversations: updatedConversations,
                                       unreadConversations: max(0, unreadConversations - 1),
                                       unreadMentions: max(0, unreadMentions - (conversation.unreadMention ? 1 : 0)))
    }

    // MARK: - Storage

    static func directoryURL(appGroupIdentifier: String) -> URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func avatarsDirectoryURL(appGroupIdentifier: String) -> URL? {
        return directoryURL(appGroupIdentifier: appGroupIdentifier)?.appendingPathComponent(avatarsDirectoryName, isDirectory: true)
    }

    static func load(appGroupIdentifier: String) -> ConversationsWidgetData? {
        guard let fileURL = directoryURL(appGroupIdentifier: appGroupIdentifier)?.appendingPathComponent(dataFileName),
              let data = try? Data(contentsOf: fileURL)
        else { return nil }

        return try? JSONDecoder().decode(ConversationsWidgetData.self, from: data)
    }

    func save(appGroupIdentifier: String) throws {
        guard let directoryURL = Self.directoryURL(appGroupIdentifier: appGroupIdentifier) else { return }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let data = try JSONEncoder().encode(self)
        // The widget reads the file while the device is locked as well
        try data.write(to: directoryURL.appendingPathComponent(Self.dataFileName), options: [.atomic, .noFileProtection])
    }

    static func remove(appGroupIdentifier: String) {
        guard let directoryURL = directoryURL(appGroupIdentifier: appGroupIdentifier) else { return }

        try? FileManager.default.removeItem(at: directoryURL)
    }
}
