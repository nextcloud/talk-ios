//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SwiftyAttributes

@objc extension TalkAccount {

    public var defaultEmojis: [String] {
        return ["👍", "❤️", "😂", "😅"]
    }

    public var frequentlyUsedEmojis: [String] {
        guard let data = self.frequentlyUsedEmojisJSONString.data(using: .utf8),
              let jsonData = try? JSONSerialization.jsonObject(with: data) as? [String: Int]
        else { return defaultEmojis }

        // First sort by value (the amount), then by key (the emoji)
        var emojis = jsonData.sorted(by: {
            $0.value != $1.value ?
            $0.value > $1.value :
            $0.key < $1.key
        }).prefix(4).map({ $0.key })

        if emojis.count < 4 {
            // Fill up to 4 emojis
            let uniqueDefaultEmojis = defaultEmojis.filter { !emojis.contains($0) }
            emojis.append(contentsOf: uniqueDefaultEmojis.prefix(4 - emojis.count))
        }

        return emojis
    }

    public static var active: TalkAccount {
        return NCDatabaseManager.sharedInstance().activeAccount()
    }
}
