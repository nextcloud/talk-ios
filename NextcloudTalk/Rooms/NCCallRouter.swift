//
// SPDX-FileCopyrightText: 2026 2M Production Electrique
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// A destination that can be called through Talk.
///
/// The distinction is intentional: a Talk user is routed through the native
/// Talk call flow, while a phone number is routed through SIP/PSTN. UI layers
/// such as CarPlay and Siri should resolve a destination first and then hand it
/// to this router instead of knowing anything about SIP themselves.
enum NCCallTarget {
    case talkUser(userId: String, displayName: String)
    case phoneNumber(number: String, displayName: String?)
    case room(NCRoom)
}

@MainActor
final class NCCallRouter {
    static let shared = NCCallRouter()

    enum CallRouterError: LocalizedError {
        case accountUnavailable
        case talkRoomCreationFailed

        var errorDescription: String? {
            switch self {
            case .accountUnavailable:
                return NSLocalizedString("The Talk account is not available", comment: "")
            case .talkRoomCreationFailed:
                return NSLocalizedString("The Talk conversation could not be created", comment: "")
            }
        }
    }

    private init() {}

    /// Route a resolved destination to the correct Talk call path.
    /// - Important: `.talkUser` never falls back to PSTN. `.phoneNumber` always
    ///   uses the telephony manager. This keeps the user's chosen call type.
    func call(_ target: NCCallTarget, for account: TalkAccount? = nil) async throws {
        let resolvedAccount = account ?? NCDatabaseManager.sharedInstance().activeAccount()

        switch target {
        case .talkUser(let userId, let displayName):
            NCLog.log("Call router: Talk user target user=\(userId)")
            let room = try await talkRoom(for: userId, account: resolvedAccount)
            startCallKit(for: room, displayName: displayName.isEmpty ? room.displayName : displayName)

        case .phoneNumber(let number, let displayName):
            NCLog.log("Call router: phone target number=\(NCTelephonyManager.shared.sanitizedPhoneNumber(number))")
            let preparedCall = try await NCTelephonyManager.shared.prepareDialOut(
                phoneNumber: number,
                for: resolvedAccount
            )
            scheduleAndStart(preparedCall, displayName: displayName)

        case .room(let room):
            guard let roomAccount = room.account else {
                throw CallRouterError.accountUnavailable
            }

            if NCTelephonyManager.shared.isPhoneRoom(room) {
                NCLog.log("Call router: existing phone room target room=\(room.token)")
                let preparedCall = try await NCTelephonyManager.shared.prepareDialOut(in: room, for: roomAccount)
                scheduleAndStart(preparedCall, displayName: room.displayName)
            } else {
                NCLog.log("Call router: native Talk room target room=\(room.token)")
                startCallKit(for: room, displayName: room.displayName)
            }
        }
    }

    private func scheduleAndStart(_ preparedCall: NCTelephonyManager.PreparedDialOut, displayName: String?) {
        NCRoomsManager.shared.scheduleSIPDialOut(
            attendeeId: preparedCall.attendeeId,
            forRoomToken: preparedCall.room.token
        )

        let callName = displayName.flatMap { $0.isEmpty ? nil : $0 } ?? preparedCall.room.displayName
        startCallKit(for: preparedCall.room, displayName: callName!)
    }

    private func startCallKit(for room: NCRoom, displayName: String) {
        guard let account = room.account else { return }

        CallKitManager.sharedInstance().startCall(
            room.token,
            withVideoEnabled: false,
            andDisplayName: displayName,
            asInitiator: !room.hasCall,
            silently: false,
            recordingConsent: false,
            withAccountId: account.accountId
        )
    }

    private func talkRoom(for userId: String, account: TalkAccount) async throws -> NCRoom {
        let accountRooms = NCDatabaseManager.sharedInstance().roomsForAccountId(account.accountId, withRealm: nil)
        if let room = accountRooms.first(where: { $0.type == .oneToOne && $0.name == userId }) {
            return room
        }

        return try await withCheckedThrowingContinuation { continuation in
            NCAPIController.sharedInstance().createRoom(
                forAccount: account,
                withInvite: userId,
                ofType: .oneToOne,
                andName: nil
            ) { room, error in
                guard error == nil, let room else {
                    continuation.resume(throwing: CallRouterError.talkRoomCreationFailed)
                    return
                }

                continuation.resume(returning: room)
            }
        }
    }
}
