//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class MentionSuggestion: NSObject {

    public var id: String
    public var label: String
    public var source: String
    public var mentionId: String?
    public var userStatus: String?

    init(dictionary: [String: Any]) {
        self.id = dictionary["id"] as? String ?? ""
        self.label = dictionary["label"] as? String ?? ""
        self.source = dictionary["source"] as? String ?? ""
        self.mentionId = dictionary["mentionId"] as? String
        self.userStatus = dictionary["status"] as? String

        super.init()
    }

    func getIdForChat() -> String {
        // When we support a mentionId serverside, we use that
        var id = self.mentionId ?? self.id

        if id.contains("/") || id.rangeOfCharacter(from: .whitespaces) != nil {
            id = "\"\(id)\""
        }

        return id
    }

    func getIdForAvatar() -> String {
        // For avatars we always want to use the actorId, so ignore a potential serverside mentionId here
        return self.id
    }

    func asMessageParameter() -> NCMessageParameter {
        let messageParameter = NCMessageParameter()

        messageParameter.parameterId = self.getIdForAvatar()
        messageParameter.name = self.label
        messageParameter.mentionDisplayName = "@\(self.label)"
        // Note: The mentionId on NCMessageParameter is different than the one on MentionSuggestion!
        messageParameter.mentionId = "@\(self.getIdForChat())"

        // Set parameter type
        if self.source == "calls" {
            messageParameter.type = "call"
        } else if self.source == "users" || self.source == "federated_users" {
            messageParameter.type = "user"
        } else if self.source == "guests" {
            messageParameter.type = "guest"
        } else if self.source == "groups" {
            messageParameter.type = "user-group"
        }

        return messageParameter
    }
}
