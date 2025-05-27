//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

public let NCAttendeeTypeUser = "users"
public let NCAttendeeTypeGroup = "groups"
public let NCAttendeeTypeCircle = "circles"
public let NCAttendeeTypeTeams = "teams"
public let NCAttendeeTypeGuest = "guests"
public let NCAttendeeTypeEmail = "emails"
public let NCAttendeeTypeFederated = "federated_users"
public let NCAttendeeTypeBots = "bots"

public let NCAttendeeBotPrefix = "bot-"

public let NCAttendeeBridgeBotId = "bridge-bot"

@objcMembers
public class NCRoomParticipant: NSObject {

    var attendeeId: Int = 0
    var actorType: String?
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
        self.actorType = dictionary["actorType"] as? String
        self.actorId = dictionary["actorId"] as? String
        self.displayName = dictionary["displayName"] as? String ?? ""
        self.inCall = dictionary["inCall"] as? CallFlag ?? []
        self.lastPing = dictionary["lastPing"] as? Int ?? 0
        self.sessionId = dictionary["sessionId"] as? String
        self.sessionIds = dictionary["sessionIds"] as? [String]
        self.userId = dictionary["userId"] as? String

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
        let allowedActorType = actorType == NCAttendeeTypeUser || actorType == NCAttendeeTypeGuest || actorType == NCAttendeeTypeEmail
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
        return !isAppUser && inCall.isEmpty && actorType == NCAttendeeTypeUser && NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilitySendCallNotification)
    }

    public var isAppUser: Bool {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        return participantId == activeAccount.userId
    }

    public var isBridgeBotUser: Bool {
        return actorType == NCAttendeeTypeUser && actorId == NCAttendeeBridgeBotId
    }

    public var isGuest: Bool {
        return participantType == .guest || participantType == .guestModerator
    }

    public var isGroup: Bool {
        return actorType == NCAttendeeTypeGroup
    }

    public var isTeam: Bool {
        return actorType == NCAttendeeTypeCircle || actorType == NCAttendeeTypeTeams
    }

    public var isFederated: Bool {
        return actorType == NCAttendeeTypeFederated
    }

    public var isOffline: Bool {
        guard let sessionId else { return false }
        return sessionId == "0" || sessionId.isEmpty
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
            detailedNameString = String(format: NSLocalizedString("%@ (%@)", comment: ""), detailedNameString, moderatorString)
        }

        // Bridge bot label
        if isBridgeBotUser {
            let botString = NSLocalizedString("bot", comment: "")
            detailedNameString = String(format: NSLocalizedString("%@ (%@)", comment: ""), detailedNameString, botString)
        }

        // Guest label
        if isGuest, !defaultGuestNameUsed {
            let guestString = NSLocalizedString("guest", comment: "")
            detailedNameString = String(format: NSLocalizedString("%@ (%@)", comment: ""), detailedNameString, guestString)
        }

        return detailedNameString
    }

    public var callIconImageName: String? {
        guard inCall.isEmpty else { return nil }

        if inCall.contains(.withVideo) {
            return "video"
        }

        if inCall.contains(.withPhone) {
            return "phone"
        }

        return "mic"
    }

}
