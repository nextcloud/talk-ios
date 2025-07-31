//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AppIntents

struct SendTalkMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Send message"

    @Parameter(title: "Message")
    var message: String

    @Parameter(title: "Account")
    var account: AccountEntity

    @Parameter(title: "Conversation")
    var room: RoomEntity

    func perform() async throws -> some IntentResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) -> Void in
            guard let talkAccount = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: account.id) else {
                let error = TalkIntentError.message(NSLocalizedString("Account not found", comment: ""))

                continuation.resume(throwing: error)
                return
            }

            NCAPIController.sharedInstance().sendChatMessage(message, toRoom: room.token, threadTitle: nil, replyTo: -1, referenceId: nil, silently: false, for: talkAccount) { error in
                if error != nil {
                    let intentError = TalkIntentError.message(NSLocalizedString("An error occurred while sending the message", comment: ""))

                    continuation.resume(throwing: intentError)
                } else {
                    continuation.resume()
                }
            }
        }

        return .result()
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$message) with \(\.$account) to \(\.$room)")
    }
}
