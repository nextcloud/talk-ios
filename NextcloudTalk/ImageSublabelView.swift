//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import NextcloudKit

struct ImageSublabelView<Label: View, Sublabel: View>: View {
    var label: () -> Label
    var sublabel: () -> Sublabel

    var image: Image?

    init(image: Image? = nil, @ViewBuilder label: @escaping () -> Label, @ViewBuilder sublabel: @escaping () -> Sublabel) {
        self.image = image
        self.label = label
        self.sublabel = sublabel
    }

    init(image: Image? = nil, @ViewBuilder label: @escaping () -> Label) where Sublabel == EmptyView {
        self.image = image
        self.label = label
        self.sublabel = { EmptyView() }
    }

    var body: some View {
        HStack {
            image?.foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading) {
                label()
                sublabel()
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
