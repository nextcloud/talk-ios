//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct ConversationListView: View {

    @EnvironmentObject private var connection: WatchConnection

    @State private var path: [WatchConversation] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let snapshot = connection.snapshot {
                    if snapshot.conversations.isEmpty {
                        PlaceholderView(systemImage: "bubble.left.and.bubble.right",
                                        text: NSLocalizedString("No conversations yet", comment: ""))
                    } else {
                        List(snapshot.conversations) { conversation in
                            NavigationLink(value: conversation) {
                                ConversationRow(conversation: conversation)
                            }
                        }
                    }
                } else if connection.hasFinishedActivation {
                    PlaceholderView(systemImage: "iphone",
                                    text: NSLocalizedString("Log in to Nextcloud Talk on your iPhone to see your conversations here", comment: "Shown on the Apple Watch"))
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Talk")
            .navigationDestination(for: WatchConversation.self) { conversation in
                ConversationView(conversation: conversation)
            }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-TalkWatchOpenSampleConversation"), path.isEmpty,
                   let conversation = WatchSnapshot.sample.conversations.first {
                    path = [conversation]
                }
                #endif
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await connection.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel(NSLocalizedString("Refresh", comment: ""))
                }
            }
        }
    }
}

struct ConversationRow: View {

    let conversation: WatchConversation

    var body: some View {
        HStack(spacing: 8) {
            InitialsAvatar(name: conversation.displayName, size: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(conversation.displayName)
                        .font(.headline)
                        .fontWeight(conversation.unreadMessages > 0 ? .bold : .regular)
                        .lineLimit(1)

                    if conversation.hasCall {
                        Image(systemName: "video.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }

                if let lastMessage = conversation.lastMessage, !lastMessage.isEmpty {
                    Text(lastMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if conversation.unreadMessages > 0 {
                Text(conversation.unreadMention ? "@" : (conversation.unreadMessages > 99 ? "99+" : "\(conversation.unreadMessages)"))
                    .font(.caption2.bold())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(conversation.unreadMention ? Color.talkAccent : Color.gray.opacity(0.4)))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct InitialsAvatar: View {

    let name: String
    let size: CGFloat

    private static let colors: [Color] = [.blue, .green, .orange, .pink, .purple, .teal, .indigo, .red]

    var body: some View {
        ZStack {
            Circle().fill(Self.colors[colorIndex])
            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var initials: String {
        return name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    // Same colors as in the widgets
    private var colorIndex: Int {
        return name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Self.colors.count
    }
}

struct PlaceholderView: View {

    let systemImage: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

extension Color {
    // The Nextcloud blue
    static let talkAccent = Color(red: 0, green: 130 / 255, blue: 201 / 255)
}
