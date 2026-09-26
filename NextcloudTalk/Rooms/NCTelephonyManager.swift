//
// SPDX-FileCopyrightText: 2026 2M Production Electrique
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

final class NCTelephonyManager {
    static let shared = NCTelephonyManager()

    struct PreparedDialOut {
        let room: NCRoom
        let attendeeId: Int
        let phoneNumber: String
    }

    enum TelephonyError: LocalizedError {
        case dialOutUnavailable
        case invalidPhoneNumber
        case roomCreationFailed
        case phoneParticipantMissing

        var errorDescription: String? {
            switch self {
            case .dialOutUnavailable:
                return NSLocalizedString("Phone dial-out is not available on this server", comment: "")
            case .invalidPhoneNumber:
                return NSLocalizedString("The phone number is invalid", comment: "")
            case .roomCreationFailed:
                return NSLocalizedString("The phone conversation could not be created", comment: "")
            case .phoneParticipantMissing:
                return NSLocalizedString("The phone participant could not be found", comment: "")
            }
        }
    }

    private init() {}

    func isDialOutAvailable(for account: TalkAccount) -> Bool {
        let database = NCDatabaseManager.sharedInstance()

        guard database.serverHasTalkCapability(.sipSupportDialOut, forAccountId: account.accountId),
              let capabilities = database.serverCapabilities(forAccountId: account.accountId)
        else {
            return false
        }

        return capabilities.callEnabled && capabilities.sipDialOutEnabled
    }

    func isPhoneRoom(_ room: NCRoom) -> Bool {
        return room.objectType == "phone_temporary" || room.objectType == "phone_legacy"
    }

    func sanitizedPhoneNumber(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "+0123456789*#")
        return String(value.unicodeScalars.filter { allowed.contains($0) })
    }

    func prepareDialOut(phoneNumber rawPhoneNumber: String, for account: TalkAccount) async throws -> PreparedDialOut {
        guard isDialOutAvailable(for: account) else {
            throw TelephonyError.dialOutUnavailable
        }

        let phoneNumber = sanitizedPhoneNumber(rawPhoneNumber)
        guard !phoneNumber.isEmpty else {
            throw TelephonyError.invalidPhoneNumber
        }

        NCLog.log("SIP dial-out requested through telephony manager: number=\(phoneNumber)")

        if let room = existingPhoneRoom(for: phoneNumber, accountId: account.accountId) {
            NCLog.log("SIP dial-out reusing existing phone room: room=\(room.token) number=\(phoneNumber)")
            return try await prepareDialOut(in: room, for: account, fallbackPhoneNumber: phoneNumber)
        }

        let objectType = NCDatabaseManager.sharedInstance().serverHasTalkCapability(.sipDirectDialIn, forAccountId: account.accountId)
            ? "phone_temporary"
            : "phone_legacy"

        let room = try await createPhoneRoom(phoneNumber: phoneNumber, objectType: objectType, account: account)
        NCLog.log("SIP dial-out room ready: room=\(room.token) objectType=\(objectType)")

        return try await prepareDialOut(in: room, for: account, fallbackPhoneNumber: phoneNumber)
    }

    func prepareDialOut(in room: NCRoom, for account: TalkAccount) async throws -> PreparedDialOut {
        guard isPhoneRoom(room) else {
            throw TelephonyError.roomCreationFailed
        }

        let roomPhoneNumber = sanitizedPhoneNumber(room.displayName.isEmpty ? room.name : room.displayName)
        return try await prepareDialOut(in: room, for: account, fallbackPhoneNumber: roomPhoneNumber)
    }

    private func prepareDialOut(in room: NCRoom, for account: TalkAccount, fallbackPhoneNumber: String) async throws -> PreparedDialOut {
        var participants = try await NCAPIController.sharedInstance().getParticipants(
            forRoom: room.token,
            forAccount: account
        )

        var phoneParticipant = participants.first(where: { $0.actorType == .phone })

        if phoneParticipant == nil {
            let phoneNumber = sanitizedPhoneNumber(fallbackPhoneNumber)
            guard !phoneNumber.isEmpty else {
                throw TelephonyError.invalidPhoneNumber
            }

            _ = try await NCAPIController.sharedInstance().addParticipant(
                phoneNumber,
                ofType: "phones",
                toRoom: room.token,
                forAccount: account
            )

            NCLog.log("SIP dial-out phone participant added: room=\(room.token) number=\(phoneNumber)")

            participants = try await NCAPIController.sharedInstance().getParticipants(
                forRoom: room.token,
                forAccount: account
            )
            phoneParticipant = participants.first(where: { $0.actorType == .phone })
        }

        guard let phoneParticipant else {
            throw TelephonyError.phoneParticipantMissing
        }

        var phoneNumber = sanitizedPhoneNumber(phoneParticipant.displayName)
        if phoneNumber.isEmpty {
            phoneNumber = sanitizedPhoneNumber(fallbackPhoneNumber)
        }

        guard !phoneNumber.isEmpty else {
            throw TelephonyError.invalidPhoneNumber
        }

        NCLog.log("SIP dial-out phone participant ready: room=\(room.token) attendee=\(phoneParticipant.attendeeId)")

        return PreparedDialOut(
            room: room,
            attendeeId: phoneParticipant.attendeeId,
            phoneNumber: phoneNumber
        )
    }

    private func existingPhoneRoom(for phoneNumber: String, accountId: String) -> NCRoom? {
        let normalizedNumber = sanitizedPhoneNumber(phoneNumber)

        return NCDatabaseManager.sharedInstance()
            .roomsForAccountId(accountId, withRealm: nil)
            .first(where: { room in
                guard isPhoneRoom(room) else { return false }

                let displayNumber = sanitizedPhoneNumber(room.displayName)
                let roomNameNumber = sanitizedPhoneNumber(room.name)
                return displayNumber == normalizedNumber || roomNameNumber == normalizedNumber
            })
    }

    private func createPhoneRoom(phoneNumber: String, objectType: String, account: TalkAccount) async throws -> NCRoom {
        try await withCheckedThrowingContinuation { continuation in
            let parameters: [String: Any] = [
                "roomType": NCRoomType.group.rawValue,
                "roomName": phoneNumber,
                "objectType": objectType,
            ]

            NCAPIController.sharedInstance().createRoom(forAccount: account, withParameters: parameters) { room, error in
                guard error == nil, let room else {
                    continuation.resume(throwing: TelephonyError.roomCreationFailed)
                    return
                }

                continuation.resume(returning: room)
            }
        }
    }
}
