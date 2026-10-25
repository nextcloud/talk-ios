//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

// What the iPhone and the Apple Watch exchange through WatchConnectivity.
// The watch has no account of its own: the iPhone sends it the conversations and does everything on the
// server for it (loading messages, sending replies and reactions), so no credentials are stored on the watch.
// This file is part of the app and of the watch app.

struct WatchConversation: Codable, Identifiable, Hashable {
    var id: String { token }

    let token: String
    let displayName: String
    // Nil for sensitive conversations, the preview is not shown there
    let lastMessage: String?
    let lastActivity: Date
    let unreadMessages: Int
    let unreadMention: Bool
    let hasCall: Bool
    let isFavorite: Bool
    let isOneToOne: Bool
    let canReact: Bool
}

struct WatchSnapshot: Codable, Equatable {
    // E.g. "Alice (cloud.example.com)", shown when nothing else is there
    let accountName: String
    let conversations: [WatchConversation]
}

struct WatchMessage: Codable, Identifiable, Hashable {
    // Int64, as Int only has 32 bits on the Apple Watch
    let id: Int64
    let author: String
    let text: String
    let date: Date
    let isOwnMessage: Bool
    // Reaction and how often it was given, in the order shown below the message
    let reactions: [WatchReaction]
}

struct WatchReaction: Codable, Hashable {
    let reaction: String
    let count: Int
    let reactedBySelf: Bool
}

// Requests from the watch, answered by the iPhone
enum WatchRequest {
    static let actionKey = "action"
    static let tokenKey = "token"
    static let textKey = "text"
    static let messageIdKey = "messageId"
    static let reactionKey = "reaction"

    // Reply keys
    static let snapshotKey = "snapshot"
    static let messagesKey = "messages"
    static let errorKey = "error"

    enum Action: String {
        // Asks the iPhone to send a fresh snapshot of the conversations
        case refresh
        // Returns the last messages of a conversation
        case messages
        case send
        case react
        case markAsRead
    }

    static let reactions = ["👍", "❤️", "😂", "😮", "😢", "🎉"]

    static func encode<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try? encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(type, from: data)
    }
}
