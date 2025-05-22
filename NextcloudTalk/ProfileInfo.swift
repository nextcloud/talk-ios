//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

public struct ProfileInfo {

    var userId: String?
    var role: String?
    var pronouns: String?
    var organisation: String?
    var address: String?
    var timezoneOffset: Int?

    init(dictionary: [String: Any]) {
        self.userId = dictionary["userId"] as? String
        self.role = dictionary["role"] as? String
        self.pronouns = dictionary["pronouns"] as? String
        self.organisation = dictionary["organisation"] as? String
        self.address = dictionary["address"] as? String
        self.timezoneOffset = dictionary["timezoneOffset"] as? Int
    }

    public func getFirstProfileLine() -> String? {
        if let role, let pronouns {
            return "\(role) · \(pronouns)"
        } else if let role {
            return role
        } else if let pronouns {
            return pronouns
        }

        return nil
    }

    public func getSecondProfileLine() -> String? {
        if let organisation, let address {
            return "\(organisation) · \(address)"
        } else if let organisation {
            return organisation
        } else if let address {
            return address
        }

        return nil
    }

    public func hasAnyInformation() -> Bool {
        return role != nil || pronouns != nil || organisation != nil || address != nil
    }

}
