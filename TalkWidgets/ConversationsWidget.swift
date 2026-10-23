//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AppIntents
import SwiftUI
import WidgetKit

struct ConversationsWidget: Widget {

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: ConversationsSnapshot.widgetKind, intent: SelectAccountIntent.self, provider: ConversationsTimelineProvider()) { entry in
            ConversationsWidgetView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("Conversations", comment: ""))
        .description(NSLocalizedString("Your recent conversations and unread messages", comment: "Description of the conversations widget"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct ConversationsEntry: TimelineEntry {
    let date: Date
    let snapshot: ConversationsSnapshot?
    let account: ConversationsSnapshot.Account?
    let avatarFolderURL: URL?
}

struct ConversationsTimelineProvider: AppIntentTimelineProvider {

    // The app group follows the "group.<app bundle identifier>" convention, the extension's bundle identifier extends the app's one
    static var containerURL: URL? {
        guard let extensionBundleIdentifier = Bundle.main.bundleIdentifier else { return nil }

        let appBundleIdentifier = extensionBundleIdentifier.components(separatedBy: ".").dropLast().joined(separator: ".")
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.\(appBundleIdentifier)")
    }

    func placeholder(in context: Context) -> ConversationsEntry {
        return ConversationsEntry(date: Date(), snapshot: .sample, account: ConversationsSnapshot.sample.accounts.first, avatarFolderURL: nil)
    }

    func snapshot(for configuration: SelectAccountIntent, in context: Context) async -> ConversationsEntry {
        let entry = self.entry(for: configuration)

        // Show an example in the widget gallery when there is nothing to show yet
        if context.isPreview, entry.account?.conversations.isEmpty ?? true {
            return self.placeholder(in: context)
        }

        return entry
    }

    func timeline(for configuration: SelectAccountIntent, in context: Context) async -> Timeline<ConversationsEntry> {
        // The app reloads the timeline whenever the conversations change, reload at midnight to update the dates
        let nextMidnight = Calendar.current.startOfDay(for: Date()).addingTimeInterval(24 * 60 * 60)

        return Timeline(entries: [self.entry(for: configuration)], policy: .after(nextMidnight))
    }

    private func entry(for configuration: SelectAccountIntent) -> ConversationsEntry {
        guard let containerURL = Self.containerURL, let snapshot = ConversationsSnapshot.load(from: containerURL) else {
            return ConversationsEntry(date: Date(), snapshot: nil, account: nil, avatarFolderURL: nil)
        }

        return ConversationsEntry(date: Date(),
                                  snapshot: snapshot,
                                  account: snapshot.account(withId: configuration.account?.id),
                                  avatarFolderURL: ConversationsSnapshot.avatarFolderURL(in: containerURL))
    }
}

// MARK: - Configuration

struct SelectAccountIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Account"

    @Parameter(title: "Account")
    var account: WidgetAccountEntity?
}

struct WidgetAccountEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static let defaultQuery = WidgetAccountQuery()

    var id: String
    var displayName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: displayName))
    }
}

struct WidgetAccountQuery: EntityQuery {

    func entities(for identifiers: [String]) async throws -> [WidgetAccountEntity] {
        return try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetAccountEntity] {
        guard let containerURL = ConversationsTimelineProvider.containerURL, let snapshot = ConversationsSnapshot.load(from: containerURL) else { return [] }

        return snapshot.accounts.map { WidgetAccountEntity(id: $0.id, displayName: $0.displayName) }
    }
}

// MARK: - Example data

extension ConversationsSnapshot {

    static let sample: ConversationsSnapshot = {
        let now = Date()
        let conversations = [
            Conversation(id: "1", displayName: "Design team", lastMessage: "Alice: The new mockups are ready", lastActivity: now.addingTimeInterval(-300),
                         unreadMessages: 4, hasUnreadMention: true, hasCall: true, avatarFileName: "", url: nil),
            Conversation(id: "2", displayName: "Anna Larsen", lastMessage: "See you tomorrow!", lastActivity: now.addingTimeInterval(-3_600),
                         unreadMessages: 1, hasUnreadMention: true, hasCall: false, avatarFileName: "", url: nil),
            Conversation(id: "3", displayName: "Marketing", lastMessage: "Tom: Campaign numbers are in", lastActivity: now.addingTimeInterval(-7_200),
                         unreadMessages: 12, hasUnreadMention: false, hasCall: false, avatarFileName: "", url: nil),
            Conversation(id: "4", displayName: "Lunch", lastMessage: "You: 12:30 at the usual place?", lastActivity: now.addingTimeInterval(-86_400),
                         unreadMessages: 0, hasUnreadMention: false, hasCall: false, avatarFileName: "", url: nil),
            Conversation(id: "5", displayName: "Support", lastMessage: "Ticket closed", lastActivity: now.addingTimeInterval(-172_800),
                         unreadMessages: 0, hasUnreadMention: false, hasCall: false, avatarFileName: "", url: nil),
            Conversation(id: "6", displayName: "Note to self", lastMessage: "Buy milk", lastActivity: now.addingTimeInterval(-259_200),
                         unreadMessages: 0, hasUnreadMention: false, hasCall: false, avatarFileName: "", url: nil),
            Conversation(id: "7", displayName: "Release planning", lastMessage: "Mia: Branch-off is on Friday", lastActivity: now.addingTimeInterval(-345_600),
                         unreadMessages: 0, hasUnreadMention: false, hasCall: false, avatarFileName: "", url: nil)
        ]

        let account = Account(id: "sample", displayName: "", unreadConversationCount: 3, conversations: conversations)
        return ConversationsSnapshot(appName: "Talk", themeColor: Color(red: 0, green: 0.51, blue: 0.79), activeAccountId: account.id, accounts: [account])
    }()
}
