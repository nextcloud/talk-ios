//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class TurnServer: NSObject {

    public var urls: [String]?
    public var username: String?
    public var credential: String?

    init(dictionary: [String: Any]) {
        super.init()

        if let turnUrl = dictionary["url"] as? String {
            urls = [turnUrl]
        } else if let turnUrls = dictionary["urls"] as? [String] {
            urls = turnUrls
        }

        if let turnUsername = dictionary["username"] as? String {
            username = turnUsername
        }

        if let turnCredential = dictionary["credential"] as? String {
            credential = turnCredential
        }
    }
}
