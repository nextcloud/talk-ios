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

        if let image = NCAPIController.sharedInstance().userProfileImage(forAccount: account, withStyle: .light) {
            // TODO: Modernization - This uses the deprecated NCUtils.roundedImage(fromImage:), which renders at
            // UITraitCollection.current.displayScale. The correct call is roundedImage(fromImage:traitCollection:),
            // but there is nothing to pass: AccountEntity is built by AccountEntityQuery (an EntityQuery protocol
            // requirement whose signature cannot take a trait collection) and is rendered out-of-process by Siri and
            // Shortcuts, so no window or display context exists here. Render the entity image at a fixed scale
            // appropriate for DisplayRepresentation instead of a display-derived one.
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
