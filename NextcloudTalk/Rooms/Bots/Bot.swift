//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

public enum BotState: Int {
    case disabled = 0
    case enabled = 1
    case noSetup = 2
}

public struct Bot: Hashable {

    public var id: Int
    public var name: String
    public var description: String?
    public var state: BotState?

    init(id: Int, name: String, description: String? = nil, state: BotState?) {
        self.id = id
        self.name = name
        self.description = description
        self.state = state
    }

    init?(dictionary: [String: Any]?) {
        guard let dictionary else { return nil }

        self.id = dictionary["id"] as? Int ?? 0
        self.name = dictionary["name"] as? String ?? ""
        self.description = dictionary["description"] as? String
        self.state = BotState(rawValue: dictionary["state"] as? Int ?? 0)
    }

}
