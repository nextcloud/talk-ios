//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import WidgetKit

@main
struct TalkWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ConversationsWidget()
        UnreadConversationsWidget()
    }
}

// MARK: - Timeline

struct ConversationsEntry: TimelineEntry {
    let date: Date
    // Nil, when no account is logged in
    let data: ConversationsWidgetData?
}

struct ConversationsProvider: TimelineProvider {

    func placeholder(in context: Context) -> ConversationsEntry {
        return ConversationsEntry(date: Date(), data: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (ConversationsEntry) -> Void) {
        // The widget gallery shows example conversations, until there are real ones
        let data = WidgetStorage.loadData() ?? (context.isPreview ? .preview : nil)
        completion(ConversationsEntry(date: Date(), data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ConversationsEntry>) -> Void) {
        // The app reloads the widgets whenever the conversations change, there's nothing to refresh on our own
        let entry = ConversationsEntry(date: Date(), data: WidgetStorage.loadData())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

// MARK: - Storage

enum WidgetStorage {

    // Set in the Info.plist, as it differs for branded apps
    static var appGroupIdentifier: String {
        return Bundle.main.object(forInfoDictionaryKey: "NCAppGroupIdentifier") as? String ?? "group.com.nextcloud.Talk"
    }

    static func loadData() -> ConversationsWidgetData? {
        return ConversationsWidgetData.load(appGroupIdentifier: appGroupIdentifier)
    }

    static func avatar(named fileName: String?) -> UIImage? {
        guard let fileName,
              let fileURL = ConversationsWidgetData.avatarsDirectoryURL(appGroupIdentifier: appGroupIdentifier)?.appendingPathComponent(fileName)
        else { return nil }

        return UIImage(contentsOfFile: fileURL.path)
    }
}

// MARK: - Preview data

extension ConversationsWidgetData {

    static let preview = ConversationsWidgetData(server: "", userId: "", conversations: [
        .init(id: "1", token: "1", displayName: "Design team", unreadMessages: 3, unreadMention: true, isFavorite: true, hasCall: false, avatarFileName: nil),
        .init(id: "2", token: "2", displayName: "Alice", unreadMessages: 1, unreadMention: false, isFavorite: true, hasCall: false, avatarFileName: nil),
        .init(id: "3", token: "3", displayName: "Weekly sync", unreadMessages: 0, unreadMention: false, isFavorite: false, hasCall: true, avatarFileName: nil),
        .init(id: "4", token: "4", displayName: "Bob", unreadMessages: 0, unreadMention: false, isFavorite: false, hasCall: false, avatarFileName: nil),
        .init(id: "5", token: "5", displayName: "Support", unreadMessages: 12, unreadMention: false, isFavorite: false, hasCall: false, avatarFileName: nil),
        .init(id: "6", token: "6", displayName: "Marketing", unreadMessages: 0, unreadMention: false, isFavorite: false, hasCall: false, avatarFileName: nil)
    ], unreadConversations: 3, unreadMentions: 1)
}

// MARK: - Helpers

extension Color {
    // The Nextcloud blue
    static let talkAccent = Color(red: 0, green: 130 / 255, blue: 201 / 255)
}

extension View {

    // iOS 17 requires the widget background to be set like this, so it can be removed e.g. in StandBy
    @ViewBuilder
    func widgetBackground<Background: View>(@ViewBuilder _ background: () -> Background) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(for: .widget, content: background)
        } else {
            self.background(background())
        }
    }
}
