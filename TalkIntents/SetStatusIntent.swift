//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AppIntents
import NextcloudKit

enum UserStatus: String, Codable, Sendable {
    case online
    case away
    case dnd
    case invisible

    func toApiParameter() -> String {
        switch self {
        case .online:
            return "online"
        case .away:
            return "away"
        case .dnd:
            return "dnd"
        case .invisible:
            return "invisible"
        }
    }
}

extension UserStatus: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: LocalizedStringResource("User status")
        )
    }

    static var caseDisplayRepresentations: [UserStatus: DisplayRepresentation] = [
        // Seems our SF Symbols for user-status do not work correctly here
        .online: DisplayRepresentation(title: "Online"),
        .away: DisplayRepresentation(title: "Away"),
        .dnd: DisplayRepresentation(title: "Do not disturb", subtitle: "Mute all notifications"),
        .invisible: DisplayRepresentation(title: "Invisible", subtitle: "Appear offline")
    ]
}

struct SetStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Set status"

    @Parameter(title: "Account")
    var account: AccountEntity

    @Parameter(title: "Status")
    var userStatus: UserStatus

    func perform() async throws -> some IntentResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) -> Void in
            guard let talkAccount = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: account.id) else {
                let error = TalkIntentError.message(NSLocalizedString("Account not found", comment: ""))

                continuation.resume(throwing: error)
                return
            }

            NCAPIController.sharedInstance().setUserStatus(userStatus.toApiParameter(), for: talkAccount) { error in
                if error != nil {
                    let intentError = TalkIntentError.message(NSLocalizedString("An error occurred while setting user status", comment: ""))

                    continuation.resume(throwing: intentError)
                } else {
                    continuation.resume()
                }
            }
        }

        return .result()
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Set status for \(\.$account) to \(\.$userStatus)")
    }
}
