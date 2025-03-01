//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AppIntents

@available(iOS 17, *)
struct SendMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Send message"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Message")
    var message: String

    @Parameter(title: "Account")
    var account: AccountEntity

    @Parameter(title: "Conversation")
    var room: RoomEntity

    func perform() async throws -> some IntentResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) -> Void in
            guard let talkAccount = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: account.id) else {
                continuation.resume(throwing: NSError())
                return
            }

            NCAPIController.sharedInstance().sendChatMessage(message, toRoom: room.token, displayName: nil, replyTo: -1, referenceId: nil, silently: false, for: talkAccount) { error in
                if error != nil {
                    continuation.resume(throwing: NSError())
                    return
                }

                continuation.resume()
            }
        }

        return .result()
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$message) with \(\.$account) to \(\.$room)")
    }
}
