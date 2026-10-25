//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

@main
struct TalkWatchApp: App {

    @StateObject private var connection = WatchConnection.shared

    var body: some Scene {
        WindowGroup {
            ConversationListView()
                .environmentObject(connection)
                .onAppear {
                    connection.activate()
                }
        }
    }
}
