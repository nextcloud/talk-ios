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

@objcMembers public class FederationInvitation: NSObject {

    public var invitationId: Int = 0
    public var remoteServer: String?
    public var remoteConversationName: String?

    init(notification: NCNotification) {
        super.init()

        self.invitationId = Int(notification.objectId) ?? 0

        guard let richParameters = notification.subjectRichParameters as? [String: AnyObject]
        else { return }

        if let roomNameObj = richParameters["roomName"] as? [String: AnyObject],
           let roomName = roomNameObj["name"] as? String {

            remoteConversationName = roomName
        }

        if let serverObj = richParameters["remoteServer"] as? [String: AnyObject],
           let server = serverObj["name"] as? String {

            remoteServer = server
        }
    }

    init(dictionary: [String: Any]) {
        super.init()

        self.invitationId = dictionary["id"] as? Int ?? 0
        self.remoteServer = dictionary["remoteServerUrl"] as? String
        self.remoteConversationName = dictionary["roomName"] as? String
    }
}
