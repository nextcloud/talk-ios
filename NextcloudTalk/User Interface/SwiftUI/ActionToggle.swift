//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import NextcloudKit

struct ActionToggle<Label: View>: View {
    @Binding var isOn: Bool
    var action: (_ newValue: Bool) async -> Void
    @ViewBuilder var label: () -> Label

    @State private var isActionRunning = false

    var body: some View {
        // Use an internal binding here, to only trigger API calls
        // when the toggle was changed, not because of a data update
        let internalIsOn = Binding<Bool>(
            get: {
                return self.isOn
            },
            set: { value in
                self.isOn = value
                self.isActionRunning = true

                Task {
                    await action(value)
                    self.isActionRunning = false
                }
            }
        )

        Toggle(isOn: internalIsOn) {
            label()
        }.disabled(isActionRunning)
    }
}
