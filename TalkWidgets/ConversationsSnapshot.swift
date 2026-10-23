//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

// The conversations shown by the widgets. The app writes it to the shared app group container, the widget extension reads it.
struct ConversationsSnapshot: Codable, Equatable {

    static let widgetKind = "ConversationsWidget"
    static let maxConversationsPerAccount = 8

    private static let fileName = "ConversationsSnapshot.json"
    private static let avatarFolderName = "WidgetAvatars"

    struct Color: Codable, Equatable {
        var red: Double
        var green: Double
        var blue: Double
    }

    struct Conversation: Codable, Equatable, Identifiable {
        // The conversation token
        var id: String
        var displayName: String
        var lastMessage: String?
        var lastActivity: Date?
        var unreadMessages: Int
        var hasUnreadMention: Bool
        var hasCall: Bool
        var avatarFileName: String
        var url: URL?
    }

    struct Account: Codable, Equatable, Identifiable {
        // The account id
        var id: String
        var displayName: String
        var unreadConversationCount: Int
        var conversations: [Conversation]
    }

    var appName: String
    var themeColor: Color
    var activeAccountId: String?
    var accounts: [Account]

    // Returns the account with the given id, falling back to the active account
    func account(withId accountId: String?) -> Account? {
        if let accountId, let account = accounts.first(where: { $0.id == accountId }) {
            return account
        }

        return accounts.first { $0.id == activeAccountId } ?? accounts.first
    }

    // MARK: - Formatting

    // A time for today, "Yesterday", a weekday within the last week and a date for anything older
    static func formattedDate(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return NSLocalizedString("Yesterday", comment: "")
        }

        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day, days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }

        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    // MARK: - Storage

    static func snapshotURL(in containerURL: URL) -> URL {
        return containerURL.appendingPathComponent(fileName)
    }

    static func avatarFolderURL(in containerURL: URL) -> URL {
        return containerURL.appendingPathComponent(avatarFolderName, isDirectory: true)
    }

    static func avatarFileName(forAccountId accountId: String, roomToken: String) -> String {
        let name = "\(accountId)-\(roomToken)".addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        return "\(name).png"
    }

    static func load(from containerURL: URL) -> ConversationsSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL(in: containerURL)) else { return nil }

        return try? JSONDecoder().decode(ConversationsSnapshot.self, from: data)
    }

    // Returns false when the stored snapshot is already up to date
    @discardableResult
    func write(to containerURL: URL) throws -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let data = try encoder.encode(self)
        let snapshotURL = Self.snapshotURL(in: containerURL)

        if let storedData = try? Data(contentsOf: snapshotURL), storedData == data {
            return false
        }

        try data.write(to: snapshotURL, options: .atomic)
        return true
    }
}
