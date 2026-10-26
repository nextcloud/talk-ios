//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import WidgetKit

// Lock screen widget with the number of unread conversations and mentions
struct UnreadConversationsWidget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ConversationsWidgetData.unreadWidgetKind, provider: ConversationsProvider()) { entry in
            UnreadConversationsWidgetView(entry: entry)
                .widgetBackground { Color.clear }
                .widgetURL(URL(string: "nextcloudtalk://"))
        }
        .configurationDisplayName(NSLocalizedString("Unread conversations", comment: "Name of the widget"))
        .description(NSLocalizedString("The number of conversations with unread messages and mentions.", comment: "Description of the unread conversations widget"))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct UnreadConversationsWidgetView: View {

    @Environment(\.widgetFamily) private var family

    let entry: ConversationsEntry

    private var unreadConversations: Int { entry.data?.unreadConversations ?? 0 }
    private var unreadMentions: Int { entry.data?.unreadMentions ?? 0 }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: unreadMentions > 0 ? "at" : "bubble.left.and.bubble.right.fill")
                        .font(.caption)
                    Text("\(unreadConversations)")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .minimumScaleFactor(0.5)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Talk", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.headline)
                Text(String(format: NSLocalizedString("Unread: %ld", comment: "Number of conversations with unread messages"), unreadConversations))
                Text(String(format: NSLocalizedString("Mentions: %ld", comment: "Number of conversations with unread mentions"), unreadMentions))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            Label(String(format: NSLocalizedString("Unread: %ld", comment: "Number of conversations with unread messages"), unreadConversations),
                  systemImage: "bubble.left.and.bubble.right.fill")
        }
    }
}
