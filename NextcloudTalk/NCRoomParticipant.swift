//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

public let NCAttendeeBotPrefix = "bot-"

public let NCAttendeeBridgeBotId = "bridge-bot"

enum AttendeeType: String {
    case user = "users"
    case group = "groups"
    case circle = "circles"
    case teams = "teams"
    case guest = "guests"
    case email = "emails"
    case federated = "federated_users"
    case bots = "bots"
}

@objcMembers
public class NCRoomParticipant: NSObject {

    var attendeeId: Int = 0
    var actorType: AttendeeType?
    var actorId: String?
    var displayName: String
    var inCall: CallFlag = []
    var lastPing: Int = 0
    var participantType: NCParticipantType?
    var sessionIds: [String]?
    var status: String?
    var statusIcon: String?
    var statusMessage: String?
    var invitedActorId: String?

    // Deprecated in conversation APIv3
    var userId: String?

    // Deprecated in conversation APIv4
    var sessionId: String?

    init(dictionary: [String: Any]) {
        self.attendeeId = dictionary["attendeeId"] as? Int ?? 0
        self.actorId = dictionary["actorId"] as? String
        self.displayName = dictionary["displayName"] as? String ?? ""
        self.inCall = dictionary["inCall"] as? CallFlag ?? []
        self.lastPing = dictionary["lastPing"] as? Int ?? 0
        self.sessionId = dictionary["sessionId"] as? String
        self.sessionIds = dictionary["sessionIds"] as? [String]
        self.userId = dictionary["userId"] as? String

        if let attendeeTypeRaw = dictionary["actorType"] as? String,
           let attendeeType = AttendeeType(rawValue: attendeeTypeRaw) {

            self.actorType = attendeeType
        }

        if let participantTypeRaw = dictionary["participantType"] as? Int,
           let participantType = NCParticipantType(rawValue: participantTypeRaw) {

            self.participantType = participantType
        }

        // Optional attributes
        self.status = dictionary["status"] as? String
        self.statusIcon = dictionary["statusIcon"] as? String
        self.statusMessage = dictionary["statusMessage"] as? String
        self.invitedActorId = dictionary["invitedActorId"] as? String

        super.init()
    }

    public var canModerate: Bool {
        return participantType == .owner || participantType == .moderator || participantType == .guestModerator
    }

    public var canBePromoted: Bool {
        let allowedActorType = actorType == .user || actorType == .guest || actorType == .email
        return !canModerate && allowedActorType
    }

    public var canBeDemoted: Bool {
        return participantType == .moderator || participantType == .guestModerator
    }

    public var canBeModerated: Bool {
        return participantType != .owner && !isAppUser
    }

    public var canBeBanned: Bool {
        return NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityBanV1) && !isGroup && !isTeam && !isFederated && !canModerate
    }

    public var canBeNotifiedAboutCall: Bool {
        return !isAppUser && inCall.isEmpty && actorType == .user && NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilitySendCallNotification)
    }

    public var isAppUser: Bool {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        return participantId == activeAccount.userId
    }

    public var isBridgeBotUser: Bool {
        return actorType == .user && actorId == NCAttendeeBridgeBotId
    }

    public var isGuest: Bool {
        return participantType == .guest || participantType == .guestModerator
    }

    public var isGroup: Bool {
        return actorType == .group
    }

    public var isTeam: Bool {
        return actorType == .circle || actorType == .teams
    }

    public var isFederated: Bool {
        return actorType == .federated
    }

    public var isOffline: Bool {
        return (sessionId == "0" || sessionId == nil) && (sessionIds ?? []).isEmpty
    }

    public var participantId: String? {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        if NCAPIController.sharedInstance().conversationAPIVersion(for: activeAccount) >= APIv3 {
            return String(attendeeId)
        }

        if let actorId {
            return actorId
        }

        if isGuest {
            return sessionId
        }

        return userId
    }

    public var detailedName: String {
        var detailedNameString = displayName
        var defaultGuestNameUsed = false

        if detailedNameString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if isGuest {
                defaultGuestNameUsed = true
                detailedNameString = NSLocalizedString("Guest", comment: "")
            } else {
                detailedNameString = NSLocalizedString("[Unknown username]", comment: "")
            }
        }

        // Moderator label
        if canModerate {
            let moderatorString = NSLocalizedString("moderator", comment: "")
            detailedNameString = String(format: "%@ (%@)", detailedNameString, moderatorString)
        }

        // Bridge bot label
        if isBridgeBotUser {
            let botString = NSLocalizedString("bot", comment: "")
            detailedNameString = String(format: "%@ (%@)", detailedNameString, botString)
        }

        // Guest label
        if isGuest, !defaultGuestNameUsed {
            let guestString = NSLocalizedString("guest", comment: "")
            detailedNameString = String(format: "%@ (%@)", detailedNameString, guestString)
        }

        return detailedNameString
    }

    public var callIconImageName: String? {
        guard !inCall.isEmpty else { return nil }

        if inCall.contains(.withVideo) {
            return "video"
        }

        if inCall.contains(.withPhone) {
            return "phone"
        }

        return "mic"
    }
}

extension Array where Element == NCRoomParticipant {

    func sortedParticipants() -> [NCRoomParticipant] {
        // Sort participants by:
        // - Participants before groups
        // - In call before online before offline
        // - Type (moderators before normal participants)
        // - Alphabetic

        self.sorted {
            if $0.isTeam != $1.isTeam {
                return !$0.isTeam && $1.isTeam
            }

            if $0.isGroup != $1.isGroup {
                return !$0.isGroup && $1.isGroup
            }

            if $0.inCall != $1.inCall {
                return !$0.inCall.isEmpty
            }

            if $0.isOffline != $1.isOffline {
                return !$0.isOffline && $1.isOffline
            }

            if $0.canModerate != $1.canModerate {
                return $0.canModerate && !$1.canModerate
            }

            return $0.displayName < $1.displayName
        }
    }

}
