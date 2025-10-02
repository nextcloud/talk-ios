//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class FederationInvitation: NSObject {

    public enum FederationInvitationState: Int {
        case pending = 0
        case accepted = 1
    }

    public var accountId: String = ""
    public var invitationId: Int = 0
    public var invitationState: FederationInvitationState = .pending
    public var inviterDisplayName: String?
    public var remoteServer: String?
    public var remoteConversationName: String?

    init(notification: NCNotification, for accountId: String) {
        super.init()

        self.accountId = accountId
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

    init(dictionary: [String: Any], for accountId: String) {
        super.init()

        self.accountId = accountId
        self.invitationId = dictionary["id"] as? Int ?? 0
        self.inviterDisplayName = dictionary["inviterDisplayName"] as? String
        self.remoteServer = dictionary["remoteServerUrl"] as? String
        self.remoteConversationName = dictionary["roomName"] as? String

        if let stateRaw = dictionary["state"] as? Int,
           let state = FederationInvitationState(rawValue: stateRaw) {

            self.invitationState = state
        }

    }
}
