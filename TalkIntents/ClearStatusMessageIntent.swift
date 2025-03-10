//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AppIntents
import NextcloudKit

struct ClearStatusMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Clear status message"

    @Parameter(title: "Account")
    var account: AccountEntity

    func perform() async throws -> some IntentResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) -> Void in
            guard let talkAccount = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: account.id) else {
                let error = TalkIntentError.message(NSLocalizedString("Account not found", comment: ""))

                continuation.resume(throwing: error)
                return
            }

            NCAPIController.sharedInstance().setupNCCommunication(for: talkAccount)

            NextcloudKit.shared.clearMessage { _, error in
                if error.errorCode != 0 {
                    let intentError = TalkIntentError.message(NSLocalizedString("An error occurred while clearing status message", comment: ""))

                    continuation.resume(throwing: intentError)
                } else {
                    continuation.resume()
                }
            }
        }

        return .result()
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Clear status message for \(\.$account)")
    }
}
