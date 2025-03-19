//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AppIntents

@available(iOS 17, *)
struct AccountEntity: AppEntity {
    var id: String
    var userDisplayName: String
    var server: String
    var imageData: Data?

    static var defaultQuery = AccountEntityQuery()
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Account"

    init(account: TalkAccount) {
        id = account.accountId
        userDisplayName = account.userDisplayName
        server = account.server.replacingOccurrences(of: "https://", with: "")

        if let image = NCAPIController.sharedInstance().userProfileImage(for: account, with: .light) {
            let roundedImage = NCUtils.roundedImage(fromImage: image)
            imageData = roundedImage.pngData()
        }
    }

    var displayRepresentation: DisplayRepresentation {
        if let imageData {
            return DisplayRepresentation(title: "\(userDisplayName)", subtitle: "\(server)", image: .init(data: imageData))
        }

        return DisplayRepresentation(title: "\(userDisplayName)", subtitle: "\(server)")
    }
}

@available(iOS 17, *)
struct AccountEntityQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [AccountEntity] {
        NCDatabaseManager.sharedInstance().allAccounts().filter({
            $0.accountId.contains(string) || $0.userDisplayName.contains(string)
        }).map { AccountEntity(account: $0) }
    }

    func suggestedEntities() async throws -> [AccountEntity] {
        NCDatabaseManager.sharedInstance().allAccounts().map { AccountEntity(account: $0) }
    }

    func entities(for identifiers: [String]) async throws -> [AccountEntity] {
        NCDatabaseManager.sharedInstance().allAccounts().filter({ identifiers.contains($0.accountId) }).map { AccountEntity(account: $0) }
    }
}
