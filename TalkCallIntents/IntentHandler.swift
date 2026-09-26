//
// SPDX-FileCopyrightText: 2026 2M Production Electrique
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Intents
import Contacts

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

        // The containing app performs the actual Talk or PSTN call.
        completion(INStartCallIntentResponse(code: .continueInApp, userActivity: nil))
    }

    private func callCandidates(for person: INPerson) -> [INPerson] {
        // If Siri already resolved one concrete phone number, that is a final
        // selection (for example after a previous disambiguation round).
        if isConcretePhone(person) {
            return [person]
        }

        var candidates: [INPerson] = []
        var seen = Set<String>()

        // App-specific Talk identities donated through INStartCallIntent.
        // Keep them distinct from PSTN choices.
        let talkMatches = ([person] + (person.siriMatches ?? [])).filter {
            guard let customIdentifier = $0.customIdentifier else { return false }
            return !customIdentifier.isEmpty
        }

        for match in talkMatches {
            let key = "talk:\(match.customIdentifier ?? match.displayName)"
            if seen.insert(key).inserted {
                candidates.append(talkCandidate(from: match))
            }
        }

        // Build one Siri choice per unique telephone number. This reproduces
        // the native Phone behaviour: Mobile / Work / Home are separate choices.
        for phoneCandidate in addressBookCandidates(for: person) {
            let number = phoneCandidate.personHandle?.value ?? ""
            let key = "phone:\(normalizedPhoneNumber(number))"
            if !number.isEmpty, seen.insert(key).inserted {
                candidates.append(phoneCandidate)
            }
        }

        // Siri sometimes already supplies phone-capable matches even if the
        // top-level INPerson contains only the spoken name.
        for match in person.siriMatches ?? [] where isConcretePhone(match) {
            let number = match.personHandle?.value ?? ""
            let key = "phone:\(normalizedPhoneNumber(number))"
            if !number.isEmpty, seen.insert(key).inserted {
                candidates.append(match)
            }
        }

        return candidates
    }

    private func talkCandidate(from person: INPerson) -> INPerson {
        // Make Talk visually / verbally distinguishable when a contact with the
        // same name also has PSTN numbers.
        guard let handle = person.personHandle else {
            return person
        }

        let displayName = person.displayName.hasSuffix(" – Talk")
            ? person.displayName
            : "\(person.displayName) – Talk"

        return INPerson(
            personHandle: handle,
            nameComponents: nil,
            displayName: displayName,
            image: person.image,
            contactIdentifier: person.contactIdentifier,
            customIdentifier: person.customIdentifier
        )
    }

    private func addressBookCandidates(for person: INPerson) -> [INPerson] {
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            NSLog("TalkCallIntents: Contacts not authorized in extension")
            return []
        }

        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]

        do {
            let contacts: [CNContact]

            if let identifier = person.contactIdentifier, !identifier.isEmpty {
                contacts = [try store.unifiedContact(withIdentifier: identifier, keysToFetch: keys)]
            } else {
                let name = person.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return [] }
                contacts = try store.unifiedContacts(
                    matching: CNContact.predicateForContacts(matchingName: name),
                    keysToFetch: keys
                )
            }

            var output: [INPerson] = []
            var seenNumbers = Set<String>()

            for contact in contacts {
                let baseName = contactDisplayName(contact, fallback: person.displayName)

                for labeledNumber in contact.phoneNumbers {
                    let number = labeledNumber.value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !number.isEmpty else { continue }

                    let normalized = normalizedPhoneNumber(number)
                    guard !normalized.isEmpty, seenNumbers.insert(normalized).inserted else { continue }

                    let localizedLabel = localizedPhoneLabel(labeledNumber.label)
                    let choiceName = localizedLabel.isEmpty ? baseName : "\(baseName) – \(localizedLabel)"
                    let handle = INPersonHandle(
                        value: number,
                        type: .phoneNumber,
                        label: intentHandleLabel(from: labeledNumber.label)
                    )

                    let candidate = INPerson(
                        personHandle: handle,
                        nameComponents: nil,
                        displayName: choiceName,
                        image: nil,
                        contactIdentifier: contact.identifier,
                        customIdentifier: nil
                    )
                    output.append(candidate)
                }
            }

            NSLog("TalkCallIntents: address book candidates for %@ = %ld", person.displayName, output.count)
            return output
        } catch {
            NSLog("TalkCallIntents: Contacts lookup failed for %@: %@", person.displayName, String(describing: error))
            return []
        }
    }

    private func contactDisplayName(_ contact: CNContact, fallback: String) -> String {
        let components = [contact.givenName, contact.familyName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return components.isEmpty ? fallback : components.joined(separator: " ")
    }

    private func localizedPhoneLabel(_ label: String?) -> String {
        guard let label, !label.isEmpty else { return "" }
        return CNLabeledValue<NSString>.localizedString(forLabel: label)
    }

    private func intentHandleLabel(from contactLabel: String?) -> INPersonHandleLabel {
        switch contactLabel {
        case CNLabelHome:
            return .home
        case CNLabelWork:
            return .work
        case CNLabelPhoneNumberMobile:
            return .mobile
        case CNLabelPhoneNumberiPhone:
            return .iPhone
        case CNLabelPhoneNumberMain:
            return .main
        case CNLabelPhoneNumberHomeFax:
            return .homeFax
        case CNLabelPhoneNumberWorkFax:
            return .workFax
        case CNLabelPhoneNumberPager:
            return .pager
        case CNLabelSchool:
            return .school
        default:
            return .other
        }
    }

    private func isConcretePhone(_ person: INPerson) -> Bool {
        guard let handle = person.personHandle,
              handle.type == .phoneNumber,
              let value = handle.value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return false
        }
        return true
    }

    private func normalizedPhoneNumber(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter(\.isNumber)
        if trimmed.hasPrefix("+") {
            return "+" + digits
        }
        return digits
    }
}
