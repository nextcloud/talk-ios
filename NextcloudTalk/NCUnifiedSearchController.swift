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
        NCAPIController.sharedInstance().setupNCCommunication(for: account)

        NextcloudKit.shared.searchProvider("talk-message",
                                           account: account.accountId,
                                           term: searchTerm,
                                           limit: limit,
                                           cursor: cursor,
                                           options: NKRequestOptions(),
                                           timeout: 30) { _, searchResult, _, _ in
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
