//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import CoreSpotlight
import UniformTypeIdentifiers

// Makes the conversations findable in the system search (Spotlight).
// Only the names and descriptions are indexed, never any messages. Sensitive conversations are not indexed at all.
class ConversationsSpotlightIndexer {

    public static let shared = ConversationsSpotlightIndexer()

    private let indexedAccountIdsKey = "spotlightIndexedAccountIds"

    // What was indexed last per account, to not index the same conversations again on every rooms update
    private var indexedSignatures = [String: String]()

    func start() {
        NotificationCenter.default.addObserver(self, selector: #selector(setNeedsUpdate), name: .NCRoomsManagerDidUpdateRooms, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setNeedsUpdate), name: .NCSettingsControllerDidChangeActiveAccount, object: nil)

        self.setNeedsUpdate()
    }

    @objc func setNeedsUpdate() {
        DispatchQueue.main.async {
            self.update()
        }
    }

    private func update() {
        guard CSSearchableIndex.isIndexingAvailable() else { return }

        let index = CSSearchableIndex.default()
        let accounts = NCDatabaseManager.sharedInstance().allAccounts()

        // Remove the conversations of accounts that were logged out
        let accountIds = Set(accounts.map(\.accountId))
        let removedAccountIds = self.indexedAccountIds.subtracting(accountIds)

        if !removedAccountIds.isEmpty {
            index.deleteSearchableItems(withDomainIdentifiers: Array(removedAccountIds))
            removedAccountIds.forEach { self.indexedSignatures.removeValue(forKey: $0) }
        }

        self.indexedAccountIds = self.indexedAccountIds.intersection(accountIds)

        guard !accounts.isEmpty else { return }

        // Rooms are only updated for the active account
        let account = NCDatabaseManager.sharedInstance().activeAccount()
        let rooms = NCDatabaseManager.sharedInstance().roomsForAccountId(account.accountId, withRealm: nil)
            .filter { !$0.isSensitive }
            .sorted { $0.internalId < $1.internalId }

        let signature = rooms.map { "\($0.internalId)\u{1F}\($0.displayName ?? "")\u{1F}\($0.roomDescription ?? "")" }.joined(separator: "\u{1E}")

        guard indexedSignatures[account.accountId] != signature else { return }

        let showAccountName = accounts.count > 1

        let items = rooms.map { room in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = room.displayName
            attributes.contentDescription = showAccountName ? account.userDisplayName : room.roomDescription
            attributes.keywords = ["Talk"]

            return CSSearchableItem(uniqueIdentifier: room.internalId, domainIdentifier: account.accountId, attributeSet: attributes)
        }

        // Replace all conversations of the account, so removed conversations are removed from the index as well
        index.deleteSearchableItems(withDomainIdentifiers: [account.accountId]) { _ in
            index.indexSearchableItems(items) { error in
                if let error {
                    NCLog.log("Could not index conversations in Spotlight: \(error.localizedDescription)")
                }
            }
        }

        indexedSignatures[account.accountId] = signature
        self.indexedAccountIds.insert(account.accountId)
    }

    private var indexedAccountIds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: indexedAccountIdsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: indexedAccountIdsKey) }
    }

    // MARK: - Opening a search result

    static func conversationURL(for userActivity: NSUserActivity) -> NSURLComponents? {
        guard userActivity.activityType == CSSearchableItemActionType,
              let internalId = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let room = NCDatabaseManager.sharedInstance().room(withInternalId: internalId),
              let account = room.account
        else { return nil }

        let urlComponents = NSURLComponents()
        urlComponents.scheme = "nextcloudtalk"
        urlComponents.host = "open-conversation"
        urlComponents.queryItems = [
            URLQueryItem(name: "server", value: account.server),
            URLQueryItem(name: "user", value: account.userId),
            URLQueryItem(name: "withRoomToken", value: room.token)
        ]

        return urlComponents
    }
}
