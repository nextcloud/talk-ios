//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class MentionSuggestion: NSObject {

    public var mention: Mention
    public var source: String
    public var userStatus: String?
    public var details: String?

    init(dictionary: [String: Any]) {
        self.mention = Mention(id: dictionary["id"] as? String ?? "", label: dictionary["label"] as? String ?? "", mentionId: dictionary["mentionId"] as? String)
        self.source = dictionary["source"] as? String ?? ""
        self.userStatus = dictionary["status"] as? String
        self.details = dictionary["details"] as? String

        super.init()
    }

    func asMessageParameter() -> NCMessageParameter {
        let messageParameter = NCMessageParameter()

        messageParameter.parameterId = mention.id
        messageParameter.name = mention.label
        messageParameter.mention = mention

        // Set parameter type
        if self.source == "calls" {
            messageParameter.type = "call"
        } else if self.source == "users" || self.source == "federated_users" {
            messageParameter.type = "user"
        } else if self.source == "guests" {
            messageParameter.type = "guest"
        } else if self.source == "groups" {
            messageParameter.type = "user-group"
        } else if self.source == "emails" {
            messageParameter.type = "email"
        } else if self.source == "teams" {
            messageParameter.type = "circle"
        }

        return messageParameter
    }
}
