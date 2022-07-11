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
import NCCommunication

@objcMembers class NCUnifiedSearchController: NSObject {

    func searchMessages(term: String, account: TalkAccount, completionHandler: @escaping (NCCSearchResult?) -> Void) {
        NCAPIController.sharedInstance().setupNCCommunication(for: account)
        NCCommunication.shared.searchProvider("talk-message", term: term, limit: 5, cursor: 5, options: NCCRequestOptions(), timeout: 30) { searchResult, _, _ in
            guard let searchResult = searchResult else {
                completionHandler(nil)
                return
            }
            completionHandler(searchResult)
        }
    }
}
