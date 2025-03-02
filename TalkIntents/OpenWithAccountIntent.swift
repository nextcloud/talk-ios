//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AppIntents

@available(iOS 17, *)
struct OpenWithAccountIntent: AppIntent {
    static var title: LocalizedStringResource = "Open with account"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Account")
    var account: AccountEntity

    func perform() async throws -> some IntentResult {
        guard NCDatabaseManager.sharedInstance().talkAccount(forAccountId: account.id) != nil else {
            throw TalkIntentError.message(NSLocalizedString("Account not found", comment: ""))
        }

        DispatchQueue.main.async {
            NCSettingsController.sharedInstance().setActiveAccountWithAccountId(account.id)
        }

        return .result()
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Open with \(\.$account)")
    }
}
