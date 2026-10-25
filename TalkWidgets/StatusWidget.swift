//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import WidgetKit

// Small home screen widget to see and change the user status with one tap (iOS 17 and later)
@available(iOS 17.0, *)
struct StatusWidget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TalkControlsState.statusWidgetKind, provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(UIColor.systemBackground) }
        }
        .configurationDisplayName(NSLocalizedString("Status", comment: "Name of the widget"))
        .description(NSLocalizedString("See and change your status.", comment: "Description of the status widget"))
        .supportedFamilies([.systemSmall])
    }
}

struct StatusEntry: TimelineEntry {
    let date: Date
    let isLoggedIn: Bool
    let status: String?
}

struct StatusProvider: TimelineProvider {

    func placeholder(in context: Context) -> StatusEntry {
        return StatusEntry(date: Date(), isLoggedIn: true, status: "online")
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(self.currentEntry(isPreview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        // The app reloads the widget whenever the status changes
        completion(Timeline(entries: [self.currentEntry(isPreview: false)], policy: .never))
    }

    private func currentEntry(isPreview: Bool) -> StatusEntry {
        let isLoggedIn = WidgetStorage.loadData() != nil
        let status = TalkControlsState.load(appGroupIdentifier: WidgetStorage.appGroupIdentifier).userStatus

        if isPreview, !isLoggedIn {
            return StatusEntry(date: Date(), isLoggedIn: true, status: "online")
        }

        return StatusEntry(date: Date(), isLoggedIn: isLoggedIn, status: status)
    }
}

struct StatusOption: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let color: Color

    static let all: [StatusOption] = [
        StatusOption(id: "online", title: NSLocalizedString("Online", comment: "User status"), systemImage: "circle.fill", color: .green),
        StatusOption(id: "away", title: NSLocalizedString("Away", comment: "User status"), systemImage: "moon.fill", color: .yellow),
        StatusOption(id: "dnd", title: NSLocalizedString("Do not disturb", comment: "User status"), systemImage: "minus.circle.fill", color: .red),
        StatusOption(id: "invisible", title: NSLocalizedString("Invisible", comment: "User status"), systemImage: "circle.dashed", color: .gray)
    ]
}

@available(iOS 17.0, *)
struct StatusWidgetView: View {

    let entry: StatusEntry

    var body: some View {
        if !entry.isLoggedIn {
            Text(NSLocalizedString("Log in to Nextcloud Talk to see your status here", comment: "Shown in a widget, when no account is logged in"))
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                let current = StatusOption.all.first { $0.id == entry.status }

                HStack(spacing: 6) {
                    Image(systemName: current?.systemImage ?? "circle")
                        .foregroundColor(current?.color ?? .secondary)
                    Text(current?.title ?? NSLocalizedString("Status", comment: ""))
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        StatusButton(option: StatusOption.all[0], isCurrent: entry.status == "online")
                        StatusButton(option: StatusOption.all[1], isCurrent: entry.status == "away")
                    }
                    GridRow {
                        StatusButton(option: StatusOption.all[2], isCurrent: entry.status == "dnd")
                        StatusButton(option: StatusOption.all[3], isCurrent: entry.status == "invisible")
                    }
                }
            }
        }
    }
}

@available(iOS 17.0, *)
private struct StatusButton: View {

    let option: StatusOption
    let isCurrent: Bool

    var body: some View {
        Button(intent: WidgetSetStatusIntent(status: option.id)) {
            Image(systemName: option.systemImage)
                .font(.title3)
                .foregroundColor(option.color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isCurrent ? option.color.opacity(0.25) : Color(UIColor.secondarySystemFill)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
