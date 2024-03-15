//
// Copyright (c) 2024 Marcel Müller <marcel-mueller@gmx.de>
//
// Author Marcel Müller <marcel-mueller@gmx.de>
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
