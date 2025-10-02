//
// SPDX-FileCopyrightText: 2025  Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct AbsenceLabelView: View {
    @Binding var absenceStatus: UserAbsence?

    var replacement: AttributedString {
        var result = AttributedString("Replacement")
        result.font = .preferredFont(for: .body, weight: .bold)
        return result
    }

    var body: some View {
        VStack(alignment: .leading) {
            if let absenceStatus, absenceStatus.isValid {
                if absenceStatus.firstDay == absenceStatus.lastDay {
                    Text(absenceStatus.firstDay.format(dateStyle: .medium))
                        .foregroundColor(.primary)
                } else {
                    Text(absenceStatus.firstDay.format(dateStyle: .medium) + " - " + absenceStatus.lastDay.format(dateStyle: .medium))
                        .foregroundColor(.primary)
                }

                if absenceStatus.hasReplacementSet {
                    // Make genstrings happy
                    let displayedString = NSLocalizedString("Replacement", comment: "Replacement in case of out of office") + ": " + absenceStatus.replacementName
                    Text(verbatim: displayedString)
                        .foregroundStyle(.primary)
                }

                Text(absenceStatus.messageOrStatus)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            } else {
                Text("Configure your next absence period")
            }
        }
    }
}
