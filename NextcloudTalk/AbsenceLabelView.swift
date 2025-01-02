//
// SPDX-FileCopyrightText: 2025  Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct AbsenceLabelView: View {
    @Binding var absenceStatus: UserAbsence?

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

                Text(absenceStatus.messageOrStatus)
                    .foregroundColor(.secondary)
            } else {
                Text(NSLocalizedString("Configure your next absence period", comment: ""))
            }
        }
    }
}
