//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AppIntents

enum TalkIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case unknown
    case message(_ message: String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .message(message):
            return "\(message)"
        case .unknown:
            return "Unknown error"
        }
    }
}
