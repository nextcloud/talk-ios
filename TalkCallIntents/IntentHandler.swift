//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Intents

final class IntentHandler: INExtension {
    override func handler(for intent: INIntent) -> Any {
        NSLog("TalkCallIntents: handler(for:) intent=%@", String(describing: type(of: intent)))

        if intent is INStartCallIntent {
            return StartCallIntentHandler()
        }

        NSLog("TalkCallIntents: unsupported intent type: %@", String(describing: type(of: intent)))
        return self
    }
}

final class StartCallIntentHandler: NSObject, INStartCallIntentHandling {
    func resolveCallCapability(
        for intent: INStartCallIntent,
        with completion: @escaping (INStartCallCallCapabilityResolutionResult) -> Void
    ) {
        NSLog("TalkCallIntents: resolveCallCapability")
        completion(.success(with: .audioCall))
    }

    func resolveDestinationType(
        for intent: INStartCallIntent,
        with completion: @escaping (INCallDestinationTypeResolutionResult) -> Void
    ) {
        NSLog("TalkCallIntents: resolveDestinationType raw=%ld", intent.destinationType.rawValue)

        switch intent.destinationType {
        case .normal, .unknown:
            completion(.success(with: .normal))
        default:
            completion(.unsupported())
        }
    }

    func resolveContacts(
        for intent: INStartCallIntent,
        with completion: @escaping ([INStartCallContactResolutionResult]) -> Void
    ) {
        let requested = intent.contacts ?? []
        NSLog("TalkCallIntents: resolveContacts requested=%ld", requested.count)

        guard !requested.isEmpty else {
            NSLog("TalkCallIntents: no contact yet; asking Siri for a person")
            completion([.needsValue()])
            return
        }

        let results = requested.map { person -> INStartCallContactResolutionResult in
            let candidates = callCandidates(for: person)

            NSLog(
                "TalkCallIntents: person=%@ candidates=%ld customId=%@ contactId=%@",
                person.displayName,
                candidates.count,
                person.customIdentifier ?? "<nil>",
                person.contactIdentifier ?? "<nil>"
            )

            switch candidates.count {
            case 0:
                // Do not reject a spoken name. The containing app can still
                // resolve it against the live Nextcloud Talk directory.
                NSLog("TalkCallIntents: no local candidate; passing spoken person to app")
                return .success(with: person)

            case 1:
                NSLog("TalkCallIntents: single destination selected: %@", candidates[0].displayName)
                return .success(with: candidates[0])

            default:
                NSLog("TalkCallIntents: requesting Siri disambiguation count=%ld", candidates.count)
                return .disambiguation(with: candidates)
            }
        }

        completion(results)
    }

    func resolveCallRecordToCallBack(
        for intent: INStartCallIntent,
        with completion: @escaping (INCallRecordResolutionResult) -> Void
    ) {
        completion(.notRequired())
    }

    func confirm(
        intent: INStartCallIntent,
        completion: @escaping (INStartCallIntentResponse) -> Void
    ) {
        let contacts = intent.contacts ?? []
        NSLog("TalkCallIntents: confirm contacts=%ld", contacts.count)

        guard !contacts.isEmpty else {
            completion(INStartCallIntentResponse(code: .failureContactNotSupportedByApp, userActivity: nil))
            return
        }

        completion(INStartCallIntentResponse(code: .ready, userActivity: nil))
    }

    func handle(
        intent: INStartCallIntent,
        completion: @escaping (INStartCallIntentResponse) -> Void
    ) {
        let contacts = intent.contacts ?? []
        NSLog("TalkCallIntents: handle contacts=%ld", contacts.count)

        guard !contacts.isEmpty else {
            completion(INStartCallIntentResponse(code: .failureContactNotSupportedByApp, userActivity: nil))
            return
        }

        // The containing app performs the actual Talk call.
        completion(INStartCallIntentResponse(code: .continueInApp, userActivity: nil))
    }

    private func callCandidates(for person: INPerson) -> [INPerson] {
        var candidates: [INPerson] = []
        var seen = Set<String>()

        let talkMatches = ([person] + (person.siriMatches ?? [])).filter {
            guard let customIdentifier = $0.customIdentifier else { return false }
            return !customIdentifier.isEmpty
        }

        for match in talkMatches {
            let key = match.customIdentifier ?? match.displayName
            if seen.insert(key).inserted {
                candidates.append(match)
            }
        }

        return candidates
    }

}
