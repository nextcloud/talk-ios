//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import NextcloudKit

struct ActionPicker<Selection: Hashable, Label: View, Content: View>: View {
    @Binding var selection: Selection
    var action: (_ newValue: Selection) async -> Void
    @ViewBuilder var label: () -> Label
    @ViewBuilder var content: () -> Content

    @State private var isActionRunning = false

    var body: some View {
        // Use an internal binding here, to only trigger API calls
        // when the selection was changed, not because of a data update
        let internalSelection = Binding<Selection>(
            get: {
                return self.selection
            },
            set: { value in
                self.selection = value
                self.isActionRunning = true

                Task {
                    await action(value)
                    self.isActionRunning = false
                }
            }
        )

        Picker(selection: internalSelection) {
            content()
        } label: {
            label()
        }
        .menuIndicator(.hidden)
        .disabled(isActionRunning)
        .multilineTextAlignment(.leading)
    }
}
