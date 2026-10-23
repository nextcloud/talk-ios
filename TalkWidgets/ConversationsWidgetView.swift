//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import WidgetKit

struct ConversationsWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: ConversationsEntry

    var body: some View {
        content
            .containerBackground(.background, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            UnreadCircularView(account: entry.account)
        case .accessoryRectangular:
            UnreadRectangularView(appName: entry.snapshot?.appName, account: entry.account)
        case .accessoryInline:
            UnreadInlineView(account: entry.account)
        default:
            if let snapshot = entry.snapshot, let account = entry.account {
                ConversationListView(snapshot: snapshot, account: account, avatarFolderURL: entry.avatarFolderURL)
            } else {
                NotLoggedInView()
            }
        }
    }
}

// MARK: - Home Screen

struct ConversationListView: View {
    @Environment(\.widgetFamily) private var family

    let snapshot: ConversationsSnapshot
    let account: ConversationsSnapshot.Account
    let avatarFolderURL: URL?

    private var themeColor: Color {
        Color(red: snapshot.themeColor.red, green: snapshot.themeColor.green, blue: snapshot.themeColor.blue)
    }

    private var maxRows: Int {
        switch family {
        case .systemSmall, .systemMedium:
            return 3
        default:
            return 7
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundStyle(themeColor)
                Text(snapshot.appName)
                    .font(.headline)
                    .lineLimit(1)

                if snapshot.accounts.count > 1, family != .systemSmall {
                    Text(account.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                UnreadBadge(unreadCount: account.unreadConversationCount, isHighlighted: true, themeColor: themeColor)
            }

            if account.conversations.isEmpty {
                Spacer(minLength: 0)
                Text(NSLocalizedString("You are not part of any conversation", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(account.conversations.prefix(maxRows)) { conversation in
                    ConversationLink(url: conversation.url) {
                        ConversationRow(conversation: conversation, avatarFolderURL: avatarFolderURL, themeColor: themeColor, isCompact: family == .systemSmall)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }
}

// Small widgets only support a single tap target, so links are only used in the larger families
struct ConversationLink<Content: View>: View {
    @Environment(\.widgetFamily) private var family

    let url: URL?
    @ViewBuilder let content: () -> Content

    var body: some View {
        if let url, family != .systemSmall {
            Link(destination: url, label: content)
        } else {
            content()
        }
    }
}

struct ConversationRow: View {
    let conversation: ConversationsSnapshot.Conversation
    let avatarFolderURL: URL?
    let themeColor: Color
    let isCompact: Bool

    var body: some View {
        HStack(spacing: isCompact ? 6 : 10) {
            ConversationAvatar(conversation: conversation, avatarFolderURL: avatarFolderURL, themeColor: themeColor, size: isCompact ? 24 : 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(conversation.displayName)
                    .font(isCompact ? .caption : .subheadline)
                    .fontWeight(conversation.unreadMessages > 0 ? .semibold : .regular)
                    .lineLimit(1)

                if !isCompact, let lastMessage = conversation.lastMessage {
                    Text(lastMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .privacySensitive()
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                if !isCompact, let lastActivity = conversation.lastActivity {
                    Text(ConversationsSnapshot.formattedDate(lastActivity))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                UnreadBadge(unreadCount: conversation.unreadMessages, isHighlighted: conversation.hasUnreadMention, themeColor: themeColor)
            }
        }
    }
}

struct ConversationAvatar: View {
    let conversation: ConversationsSnapshot.Conversation
    let avatarFolderURL: URL?
    let themeColor: Color
    let size: CGFloat

    var body: some View {
        avatar
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(alignment: .bottomTrailing) {
                if conversation.hasCall {
                    Image(systemName: "phone.circle.fill")
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(.white, .green)
                        .offset(x: 3, y: 3)
                }
            }
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarFolderURL, let image = UIImage(contentsOfFile: avatarFolderURL.appendingPathComponent(conversation.avatarFileName).path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Text(conversation.displayName.prefix(1).uppercased())
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(themeColor)
        }
    }
}

struct UnreadBadge: View {
    let unreadCount: Int
    let isHighlighted: Bool
    let themeColor: Color

    var body: some View {
        if unreadCount > 0 {
            Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isHighlighted ? Color.white : Color.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(isHighlighted ? themeColor : Color.secondary.opacity(0.25)))
        }
    }
}

struct NotLoggedInView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("Log in to see your conversations", comment: "Shown in the conversations widget before the first login"))
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Lock Screen

struct UnreadCircularView: View {
    let account: ConversationsSnapshot.Account?

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.caption)
                Text(verbatim: "\(account?.unreadConversationCount ?? 0)")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(unreadConversationsText(account?.unreadConversationCount ?? 0))
    }
}

struct UnreadRectangularView: View {
    let appName: String?
    let account: ConversationsSnapshot.Account?

    var body: some View {
        let unreadConversations = account?.conversations.filter { $0.unreadMessages > 0 } ?? []

        VStack(alignment: .leading, spacing: 1) {
            Label(appName ?? "", systemImage: "bubble.left.and.bubble.right.fill")
                .font(.headline)
                .widgetAccentable()

            if let account, account.unreadConversationCount > 0 {
                Text(unreadConversations.map(\.displayName).joined(separator: ", "))
                    .font(.caption)
                    .lineLimit(1)
                    .privacySensitive()
                Text(unreadConversationsText(account.unreadConversationCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(NSLocalizedString("You have no unread messages.", comment: ""))
                    .font(.caption)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct UnreadInlineView: View {
    let account: ConversationsSnapshot.Account?

    var body: some View {
        Label(unreadConversationsText(account?.unreadConversationCount ?? 0), systemImage: "bubble.left.and.bubble.right.fill")
    }
}

private func unreadConversationsText(_ count: Int) -> String {
    return String.localizedStringWithFormat(NSLocalizedString("%ld conversations with unread messages", comment: ""), count)
}
