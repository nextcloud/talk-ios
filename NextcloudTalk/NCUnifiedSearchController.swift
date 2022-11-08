//
// Copyright (c) 2022 Ivan Sein <ivan@nextcloud.com>
//
// Author Ivan Sein <ivan@nextcloud.com>
//
// GNU GPL version 3 or any later version
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
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
