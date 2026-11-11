//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import NextcloudKit

@objcMembers class NCUnifiedSearchController: NSObject {

    var account: TalkAccount
    var searchTerm: String
    var cursor: Int = 0
    let limit: Int = 10
    var showMore: Bool = false
    var entries: [NKSearchEntry] = []

    init(account: TalkAccount, searchTerm: String) {
        self.account = account
        self.searchTerm = searchTerm
    }

    func searchMessages(completionHandler: @escaping ([NKSearchEntry]?) -> Void) {
        NCAPIController.sharedInstance().setupNCCommunication(forAccount: account)

        Task { @MainActor in
            let (searchResult, _) = await NextcloudKit.shared.unifiedSearch(providerId: "talk-message",
                                                                            term: searchTerm,
                                                                            limit: limit,
                                                                            cursor: cursor,
                                                                            timeout: 30,
                                                                            account: account.accountId,
                                                                            options: .defaultRequestOptions())
            guard let searchResult = searchResult else {
                completionHandler(nil)
                return
            }
            self.entries.append(contentsOf: searchResult.entries)
            self.cursor = searchResult.cursor ?? 0
            self.showMore = searchResult.entries.count == self.limit
            completionHandler(self.entries)
        }
    }
}
