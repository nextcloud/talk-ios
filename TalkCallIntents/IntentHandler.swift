//
//  IntentHandler.swift
//  TalkCallIntents
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Intents

final class IntentHandler: INExtension {

    // MARK: - Intent routing

    override func handler(for intent: INIntent) -> Any {
        switch intent {
        case is INStartCallIntent:
            return StartCallIntentHandler()

        default:
            assertionFailure("Unhandled Siri intent: \(type(of: intent))")
            return self
        }
    }
}


// MARK: - Start Call

final class StartCallIntentHandler: NSObject, INStartCallIntentHandling {

    // MARK: Configuration

    private enum Constants {
        static let userActivityType = "com.nextcloud.Talk.startCall"

        static let activityContactsKey = "contacts"
        static let activityCallCapabilityKey = "callCapability"
        static let activityDestinationTypeKey = "destinationType"
        static let activityCallRecordIdentifierKey = "callRecordIdentifier"
    }


    // MARK: - Resolve call capability

    func resolveCallCapability(
        for intent: INStartCallIntent,
        with completion: @escaping (INStartCallCallCapabilityResolutionResult) -> Void
    ) {

        switch intent.callCapability {

        case .audioCall:
            completion(.success(with: .audioCall))

        case .videoCall:
            completion(.success(with: .audioCall))

        case .unknown:
            completion(.success(with: .audioCall))

        @unknown default:
            completion(.success(with: .audioCall))
        }
    }


    // MARK: - Resolve destination

    func resolveDestinationType(
        for intent: INStartCallIntent,
        with completion: @escaping (INCallDestinationTypeResolutionResult) -> Void
    ) {

        switch intent.destinationType {

        case .normal:
            completion(.success(with: .normal))

        case .emergency:
            completion(.unsupported())

        case .voicemail:
            completion(.unsupported())

        case .redial:
            completion(.success(with: .redial))

        case .unknown:
            completion(.success(with: .normal))

        @unknown default:
            completion(.unsupported())
        }
    }


    // MARK: - Resolve contacts

    func resolveContacts(
        for intent: INStartCallIntent,
        with completion: @escaping ([INPersonResolutionResult]) -> Void
    ) {
        guard let contacts = intent.contacts, !contacts.isEmpty else {
            completion([
                .needsValue()
            ])
            return
        }

        let results = contacts.map { person -> INPersonResolutionResult in
            .success(with: person)
        }

        completion(results)
    }


    // MARK: - Resolve call-back record

    func resolveCallRecordToCallBack(
        for intent: INStartCallIntent,
        with completion: @escaping (INCallRecordResolutionResult) -> Void
    ) {
        guard let callRecord = intent.callRecordToCallBack else {
            /*
             * Ce paramètre n'est utile que pour un rappel.
             *
             * Une demande normale "appelle Paul avec Talk" n'en a pas besoin.
             */
            completion(.notRequired())
            return
        }

        completion(.success(with: callRecord))
    }


    // MARK: - Confirm

    func confirm(
        intent: INStartCallIntent,
        completion: @escaping (INStartCallIntentResponse) -> Void
    ) {

        let hasContacts = !(intent.contacts?.isEmpty ?? true)
        let hasCallRecord = intent.callRecordToCallBack != nil

        guard hasContacts || hasCallRecord else {
            completion(
                INStartCallIntentResponse(
                    code: .failureContactNotSupportedByApp,
                    userActivity: nil
                )
            )
            return
        }

        completion(
            INStartCallIntentResponse(
                code: .ready,
                userActivity: nil
            )
        )
    }


    // MARK: - Handle

    func handle(
        intent: INStartCallIntent,
        completion: @escaping (INStartCallIntentResponse) -> Void
    ) {

        guard
            !(intent.contacts?.isEmpty ?? true)
            || intent.callRecordToCallBack != nil
        else {
            completion(
                INStartCallIntentResponse(
                    code: .failureContactNotSupportedByApp,
                    userActivity: nil
                )
            )
            return
        }

        let activity = makeUserActivity(from: intent)

        completion(
            INStartCallIntentResponse(
                code: .continueInApp,
                userActivity: activity
            )
        )
    }


    // MARK: - User activity

    private func makeUserActivity(
        from intent: INStartCallIntent
    ) -> NSUserActivity {

        let activity = NSUserActivity(
            activityType: Constants.userActivityType
        )

        activity.title = NSLocalizedString(
            "Start a Talk call",
            comment: "Siri activity used to start a Talk call"
        )

        activity.isEligibleForHandoff = false
        activity.isEligibleForSearch = false
        activity.isEligibleForPublicIndexing = false

        var userInfo: [String: Any] = [:]

        if let contacts = intent.contacts {
            userInfo[Constants.activityContactsKey] =
                contacts.compactMap(Self.serialisePerson)
        }

        userInfo[Constants.activityCallCapabilityKey] =
            serialiseCallCapability(intent.callCapability)

        userInfo[Constants.activityDestinationTypeKey] =
            serialiseDestinationType(intent.destinationType)

        if let callRecord = intent.callRecordToCallBack {
            userInfo[Constants.activityCallRecordIdentifierKey] =
                callRecord.identifier
        }

        activity.userInfo = userInfo

        return activity
    }


    // MARK: - Serialisation

    private static func serialisePerson(
        _ person: INPerson
    ) -> [String: String]? {

        var result: [String: String] = [:]

        if let customIdentifier = person.customIdentifier,
           !customIdentifier.isEmpty {
            result["customIdentifier"] = customIdentifier
        }

        let displayName = person.displayName

        if !displayName.isEmpty {
            result["displayName"] = displayName
        }

        if let contactIdentifier = person.contactIdentifier,
           !contactIdentifier.isEmpty {
            result["contactIdentifier"] = contactIdentifier
        }

        if let handle = person.personHandle {

            if let value = handle.value,
               !value.isEmpty {
                result["handle"] = value
            }

            result["handleType"] =
                serialisePersonHandleType(handle.type)
        }

        return result.isEmpty ? nil : result
    }


    private static func serialisePersonHandleType(
        _ type: INPersonHandleType
    ) -> String {

        switch type {

        case .unknown:
            return "unknown"

        case .emailAddress:
            return "email"

        case .phoneNumber:
            return "phone"

        @unknown default:
            return "unknown"
        }
    }


    private func serialiseCallCapability(
        _ capability: INCallCapability
    ) -> String {

        switch capability {

        case .unknown:
            return "unknown"

        case .audioCall:
            return "audio"

        case .videoCall:
            return "video"

        @unknown default:
            return "unknown"
        }
    }


    private func serialiseDestinationType(
        _ destination: INCallDestinationType
    ) -> String {

        switch destination {

        case .unknown:
            return "unknown"

        case .normal:
            return "normal"

        case .emergency:
            return "emergency"

        case .voicemail:
            return "voicemail"

        case .redial:
            return "redial"

        @unknown default:
            return "unknown"
        }
    }
}
