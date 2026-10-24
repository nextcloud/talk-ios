//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Contacts

public extension Notification.Name {
    static let NCContactsManagerContactsUpdated = Notification.Name(rawValue: "NCContactsManagerContactsUpdatedNotification")
    static let NCContactsManagerContactsAccessUpdated = Notification.Name(rawValue: "NCContactsManagerContactsAccessUpdatedNotification")
}

class NCContactsManager: NSObject {

    private static let shared = NCContactsManager()

    static func sharedInstance() -> NCContactsManager {
        return shared
    }

    private let contactStore = CNContactStore()

    func requestContactsAccess(_ completionHandler: @escaping (Bool) -> Void) {
        contactStore.requestAccess(for: .contacts) { granted, _ in
            completionHandler(granted)
            NotificationCenter.default.post(name: .NCContactsManagerContactsAccessUpdated, object: self)
        }
    }

    func isContactAccessDetermined() -> Bool {
        return CNContactStore.authorizationStatus(for: .contacts) != .notDetermined
    }

    func isContactAccessAuthorized() -> Bool {
        return CNContactStore.authorizationStatus(for: .contacts) == .authorized
    }

    // Update address book contacts and search for matches in the server only once per day
    private func isTimeToSyncContacts() -> Bool {
        let lastUpdate = Date(timeIntervalSince1970: TimeInterval(NCDatabaseManager.sharedInstance().activeAccount().lastContactSync))
        return !Calendar.current.isDate(lastUpdate, inSameDayAs: Date())
    }

    func searchInServer(forAddressBookContacts forceSync: Bool) {
        guard NCSettingsController.sharedInstance().isContactSyncEnabled() else { return }

        guard isContactAccessAuthorized(), isTimeToSyncContacts() || forceSync else {
            if !isContactAccessDetermined() {
                requestContactsAccess { granted in
                    if granted {
                        self.searchInServer(forAddressBookContacts: true)
                    }
                }
            }

            return
        }

        var phoneNumbersDict: [String: [String]] = [:]
        var contacts: [ABContact] = []
        let updateTimestamp = Int(Date().timeIntervalSince1970)

        let keysToFetch = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)

        try? contactStore.enumerateContacts(with: request) { contact, _ in
            // "digits" is the number without formatting, only reachable via KVC
            let phoneNumbers = contact.phoneNumbers.compactMap { $0.value.value(forKey: "digits") as? String }

            guard !phoneNumbers.isEmpty else { return }

            let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
            contacts.append(ABContact(value: [
                "identifier": contact.identifier,
                "name": name,
                "phoneNumbers": phoneNumbers,
                "lastUpdate": updateTimestamp
            ]))

            phoneNumbersDict[contact.identifier] = phoneNumbers
        }

        updateAddressBookCopy(withContacts: contacts, andTimestamp: updateTimestamp)
        searchForPhoneNumbers(phoneNumbersDict, forAccount: NCDatabaseManager.sharedInstance().activeAccount())
    }

    private func updateAddressBookCopy(withContacts contacts: [ABContact], andTimestamp timestamp: Int) {
        RLMRealm.writeTransaction { realm in
            for contact in contacts {
                if let managedABContact = ABContact.objects(where: "identifier = %@", contact.identifier).firstObject() as? ABContact {
                    managedABContact.name = contact.name
                    managedABContact.phoneNumbers = contact.phoneNumbers
                    managedABContact.lastUpdate = contact.lastUpdate
                } else {
                    realm.add(contact)
                }
            }

            // Delete old contacts and the nc contacts matched with them
            let managedABContactsToBeDeleted = ABContact.objects(with: NSPredicate(format: "lastUpdate != %ld", timestamp))

            for case let managedABContact as ABContact in managedABContactsToBeDeleted {
                realm.deleteObjects(NCContact.objects(with: NSPredicate(format: "identifier = %@", managedABContact.identifier)))
            }

            realm.deleteObjects(managedABContactsToBeDeleted)

            NSLog("Address Book Contacts updated")
        }
    }

    private func searchForPhoneNumbers(_ phoneNumbers: [String: [String]], forAccount account: TalkAccount) {
        let accountId = account.accountId
        let userId = account.userId

        NCAPIController.sharedInstance().searchContacts(forAccount: account, withPhoneNumbers: phoneNumbers) { contacts, error in
            guard error == nil else { return }

            RLMRealm.writeTransaction { realm in
                let updateTimestamp = Int(Date().timeIntervalSince1970)

                for (identifier, cloudId) in contacts ?? [:] {
                    let contact = NCContact()
                    contact.identifier = identifier
                    contact.cloudId = cloudId
                    contact.lastUpdate = updateTimestamp
                    contact.accountId = accountId
                    contact.internalId = "\(accountId)@\(identifier)"

                    // Filter out app user (it could have its own phone number in address book)
                    if contact.userId() == userId {
                        continue
                    }

                    if let managedNCContact = NCContact.objects(where: "identifier = %@ AND accountId = %@", identifier, accountId).firstObject() as? NCContact {
                        managedNCContact.cloudId = contact.cloudId
                        managedNCContact.lastUpdate = contact.lastUpdate
                    } else {
                        realm.add(contact)
                    }
                }

                // Delete old contacts
                realm.deleteObjects(NCContact.objects(with: NSPredicate(format: "accountId = %@ AND lastUpdate != %ld", accountId, updateTimestamp)))

                // Update last sync for account
                let managedAccount = TalkAccount.objects(where: "accountId = %@", accountId).firstObject() as? TalkAccount
                managedAccount?.lastContactSync = updateTimestamp

                NSLog("Matched NC Contacts updated")
            }

            NotificationCenter.default.post(name: .NCContactsManagerContactsUpdated, object: self)
        }
    }

    func removeStoredContacts() {
        RLMRealm.writeTransaction { realm in
            // Remove stored contacts for active account
            if let account = TalkAccount.objects(where: "active = true").firstObject() as? TalkAccount {
                realm.deleteObjects(NCContact.objects(with: NSPredicate(format: "accountId = %@", account.accountId)))
                account.lastContactSync = 0
            }

            // If there are no other account with contact sync enabled -> delete address book copy
            if TalkAccount.objects(where: "hasContactSyncEnabled = true AND active = false").firstObject() == nil {
                realm.deleteObjects(ABContact.allObjects())
            }
        }
    }
}
