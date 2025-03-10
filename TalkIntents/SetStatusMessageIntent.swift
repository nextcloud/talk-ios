//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AppIntents
import NextcloudKit

enum UserStatusClearAt: String, Codable, Sendable {
    case dontClear
    case thirtyMinutes
    case oneHour
    case fourHours
    case today
    case thisWeek
}

extension UserStatusClearAt: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: LocalizedStringResource("Clear status message after")
        )
    }

    static var caseDisplayRepresentations: [UserStatusClearAt: DisplayRepresentation] = [
        .dontClear: DisplayRepresentation(title: "Don't clear"),
        .thirtyMinutes: DisplayRepresentation(title: "30 minutes"),
        .oneHour: DisplayRepresentation(title: "1 hour"),
        .fourHours: DisplayRepresentation(title: "4 hours"),
        .today: DisplayRepresentation(title: "Today"),
        .thisWeek: DisplayRepresentation(title: "This week")
    ]

    public func getTimeInterval() -> TimeInterval {
        // See: UserStatusMessageSwiftUIView.swift
        let now = Date()
        let calendar = Calendar.current
        let gregorian = Calendar(identifier: .gregorian)
        let midnight = calendar.startOfDay(for: now)

        switch self {
        case .thirtyMinutes:
            return now.addingTimeInterval(1800).timeIntervalSince1970
        case .oneHour:
            return now.addingTimeInterval(3600).timeIntervalSince1970
        case .fourHours:
            return now.addingTimeInterval(14400).timeIntervalSince1970
        case .today:
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: midnight) else { return 0 }

            return tomorrow.timeIntervalSince1970
        case .thisWeek:
            guard let startweek = gregorian.date(from: gregorian.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else { return 0 }
            guard let endweek = gregorian.date(byAdding: .day, value: 6, to: startweek) else { return 0 }

            return endweek.timeIntervalSince1970
        default:
            return 0
        }
    }
}

struct SetStatusMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Set status message"

    @Parameter(title: "Account")
    var account: AccountEntity

    @Parameter(title: "Status message")
    var statusMessage: String

    @Parameter(title: "Clear status message after")
    var clearAt: UserStatusClearAt

    func perform() async throws -> some IntentResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) -> Void in
            guard let talkAccount = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: account.id) else {
                let error = TalkIntentError.message(NSLocalizedString("Account not found", comment: ""))

                continuation.resume(throwing: error)
                return
            }

            NCAPIController.sharedInstance().setupNCCommunication(for: talkAccount)
            NextcloudKit.shared.setCustomMessageUserDefined(statusIcon: nil, message: statusMessage, clearAt: clearAt.getTimeInterval()) { _, error in
                if error.errorCode != 0 {
                    let intentError = TalkIntentError.message(NSLocalizedString("An error occurred while setting status message", comment: ""))

                    continuation.resume(throwing: intentError)
                } else {
                    continuation.resume()
                }
            }
        }

        return .result()
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Set status message for \(\.$account) to \(\.$statusMessage) and reset after \(\.$clearAt)")
    }
}
