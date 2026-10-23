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
        CallLiveActivityWidget()
    }
}
