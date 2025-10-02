//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import NextcloudKit

struct ButtonContainerSwiftUI<Content: View>: View {
    var content: () -> Content

    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        if horizontalSizeClass == .compact {
            VStack(spacing: 10, content: content)
                .padding(.bottom, 16)
        } else {
            HStack(spacing: 10) {
                Spacer()
                content()
                Spacer()
            }
            .padding(.bottom, 16)
        }
    }
}
