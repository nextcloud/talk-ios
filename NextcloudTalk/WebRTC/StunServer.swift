//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class StunServer: NSObject {

    public var urls: [String]?

    init(dictionary: [String: Any]) {
        super.init()

        if let stunUrl = dictionary["url"] as? String {
            urls = [stunUrl]
        } else if let stunUrls = dictionary["urls"] as? [String] {
            urls = stunUrls
        }
    }
}
