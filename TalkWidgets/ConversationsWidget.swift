//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import WidgetKit

// Home screen widget with the favorite conversations, filled up with the most recent ones
struct ConversationsWidget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ConversationsWidgetData.conversationsWidgetKind, provider: ConversationsProvider()) { entry in
            ConversationsWidgetView(entry: entry)
                .widgetBackground { Color(UIColor.systemBackground) }
        }
        .configurationDisplayName(NSLocalizedString("Conversations", comment: "Name of the widget"))
        .description(NSLocalizedString("Your favorite and most recent conversations.", comment: "Description of the conversations widget"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ConversationsWidgetView: View {

    @Environment(\.widgetFamily) private var family

    let entry: ConversationsEntry

    var body: some View {
        if let data = entry.data {
            switch family {
            case .systemSmall:
                SmallConversationsView(data: data)
            case .systemMedium:
                ConversationsGridView(data: data, conversations: Array(data.conversations.prefix(4)))
            default:
                ConversationsListView(data: data, conversations: Array(data.conversations.prefix(6)))
            }
        } else {
            Text(NSLocalizedString("Log in to Nextcloud Talk to see your conversations here", comment: "Shown in a widget, when no account is logged in"))
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Small

struct SmallConversationsView: View {

    let data: ConversationsWidgetData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundColor(.talkAccent)
                Spacer()
                if data.unreadMentions > 0 {
                    UnreadBadge(text: "@", isMention: true)
                }
            }

            Text("\(data.unreadConversations)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)

            Text(NSLocalizedString("Unread conversations", comment: "Shown in a widget below the number of conversations with unread messages"))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            Spacer(minLength: 0)

            // The most recent unread conversation, or the first favorite
            if let conversation = data.conversations.first(where: { $0.unreadMessages > 0 }) ?? data.conversations.first {
                Text(conversation.displayName)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .privacySensitive()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Medium

struct ConversationsGridView: View {

    let data: ConversationsWidgetData
    let conversations: [ConversationsWidgetData.Conversation]

    var body: some View {
        if conversations.isEmpty {
            NoConversationsView()
        } else {
            HStack(alignment: .top, spacing: 8) {
                ForEach(conversations) { conversation in
                    ConversationLink(url: data.openURL(for: conversation)) {
                        VStack(spacing: 6) {
                            ConversationAvatar(conversation: conversation, size: 52)
                                .overlay(alignment: .topTrailing) {
                                    if conversation.unreadMessages > 0 {
                                        UnreadBadge(conversation: conversation)
                                            .offset(x: 6, y: -4)
                                    }
                                }

                            Text(conversation.displayName)
                                .font(.caption)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .privacySensitive()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

// MARK: - Large

struct ConversationsListView: View {

    let data: ConversationsWidgetData
    let conversations: [ConversationsWidgetData.Conversation]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundColor(.talkAccent)
                Text(NSLocalizedString("Conversations", comment: ""))
                    .font(.headline)
                Spacer()
            }

            if conversations.isEmpty {
                NoConversationsView()
            } else {
                ForEach(conversations) { conversation in
                    HStack(spacing: 8) {
                        ConversationLink(url: data.openURL(for: conversation)) {
                            HStack(spacing: 10) {
                                ConversationAvatar(conversation: conversation, size: 36)

                                Text(conversation.displayName)
                                    .font(.subheadline.weight(conversation.unreadMessages > 0 ? .semibold : .regular))
                                    .lineLimit(1)
                                    .privacySensitive()

                                Spacer(minLength: 4)

                                if conversation.hasCall {
                                    Image(systemName: "video.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                }

                                if conversation.isFavorite {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                        .font(.caption2)
                                }

                                if conversation.unreadMessages > 0 {
                                    UnreadBadge(conversation: conversation)
                                }
                            }
                        }

                        if conversation.unreadMessages > 0 {
                            MarkAsReadButton(data: data, conversation: conversation)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Components

// Marks a conversation as read without opening the app (iOS 17 and later)
struct MarkAsReadButton: View {

    let data: ConversationsWidgetData
    let conversation: ConversationsWidgetData.Conversation

    var body: some View {
        if #available(iOSApplicationExtension 17.0, *) {
            Button(intent: WidgetMarkAsReadIntent(server: data.server, userId: data.userId, token: conversation.token)) {
                Image(systemName: "checkmark.circle")
                    .font(.body)
                    .foregroundColor(.talkAccent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("Mark as read", comment: ""))
        }
    }
}

struct ConversationLink<Content: View>: View {

    let url: URL?
    @ViewBuilder let content: () -> Content

    var body: some View {
        if let url {
            Link(destination: url, label: content)
        } else {
            content()
        }
    }
}

struct NoConversationsView: View {
    var body: some View {
        Text(NSLocalizedString("No conversations yet", comment: "Shown in a widget"))
            .font(.footnote)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct UnreadBadge: View {

    let text: String
    let isMention: Bool

    init(text: String, isMention: Bool) {
        self.text = text
        self.isMention = isMention
    }

    init(conversation: ConversationsWidgetData.Conversation) {
        self.text = conversation.unreadMessages > 99 ? "99+" : "\(conversation.unreadMessages)"
        self.isMention = conversation.unreadMention
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundColor(isMention ? .white : .primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(isMention ? Color.talkAccent : Color(UIColor.systemGray5)))
    }
}

struct ConversationAvatar: View {

    let conversation: ConversationsWidgetData.Conversation
    let size: CGFloat

    private static let colors: [Color] = [.blue, .green, .orange, .pink, .purple, .teal, .indigo, .red]

    var body: some View {
        Group {
            if let image = WidgetStorage.avatar(named: conversation.avatarFileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Self.colors[colorIndex]
                    Text(initials)
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: String {
        return conversation.displayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    // Stable over launches, unlike hashValue
    private var colorIndex: Int {
        return conversation.displayName.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Self.colors.count
    }
}
