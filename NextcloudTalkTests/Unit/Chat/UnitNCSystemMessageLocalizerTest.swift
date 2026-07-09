//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitNCSystemMessageLocalizerTest: TestBaseRealm {

    private lazy var account: TalkAccount = {
        let account = TalkAccount()
        account.userId = "admin"
        return account
    }()

    // Builds a "message_deleted" system message (with the deleter as actor) and its parent,
    // the deleted message (with the original author as actor and the deleter as the {actor}
    // message parameter).
    private func deletedMessage(authorId: String, authorType: String, deleterId: String, deleterType: String, deleterName: String) -> (message: NCChatMessage, parent: NCChatMessage) {
        let isGuestDeleter = deleterType == "guests"

        let parent = NCChatMessage()
        parent.actorId = authorId
        parent.actorType = authorType
        parent.message = "Message deleted by {actor}"
        parent.messageParametersJSONString = """
        {
            "actor": {
                "type": "\(isGuestDeleter ? "guest" : "user")",
                "id": "\(isGuestDeleter ? "guest/\(deleterId)" : deleterId)",
                "name": "\(deleterName)"
            }
        }
        """

        let message = NCChatMessage()
        message.systemMessage = "message_deleted"
        message.actorId = deleterId
        message.actorType = deleterType

        return (message, parent)
    }

    // Applies the localized text to the parent (as done when storing the chat relay message)
    // and returns the parsed message, with a potential {actor} parameter substituted.
    private func parsedDeletedMessage(for parent: NCChatMessage, withLocalizedMessage localizedMessage: String) -> String? {
        parent.message = localizedMessage
        return parent.parsedMessage()?.string
    }

    func testDeletedMessageLocalizationSelfIsDeleter() throws {
        let (message, parent) = deletedMessage(authorId: "alice", authorType: "users", deleterId: "admin", deleterType: "users", deleterName: "Admin")

        let localizedMessage = NCSystemMessageLocalizer.localizedDeletedMessage(for: message, withParent: parent, account: account)
        XCTAssertEqual(localizedMessage, "Message deleted by you")
        XCTAssertEqual(parsedDeletedMessage(for: parent, withLocalizedMessage: localizedMessage), "Message deleted by you")
    }

    func testDeletedMessageLocalizationAuthorIsDeleter() throws {
        let (message, parent) = deletedMessage(authorId: "alice", authorType: "users", deleterId: "alice", deleterType: "users", deleterName: "Alice")

        let localizedMessage = NCSystemMessageLocalizer.localizedDeletedMessage(for: message, withParent: parent, account: account)
        XCTAssertEqual(localizedMessage, "Message deleted by author")
        XCTAssertEqual(parsedDeletedMessage(for: parent, withLocalizedMessage: localizedMessage), "Message deleted by author")
    }

    func testDeletedMessageLocalizationGuestAuthorIsDeleter() throws {
        let (message, parent) = deletedMessage(authorId: "guestSessionHash", authorType: "guests", deleterId: "guestSessionHash", deleterType: "guests", deleterName: "Guest user")

        let localizedMessage = NCSystemMessageLocalizer.localizedDeletedMessage(for: message, withParent: parent, account: account)
        XCTAssertEqual(localizedMessage, "Message deleted by author")
        XCTAssertEqual(parsedDeletedMessage(for: parent, withLocalizedMessage: localizedMessage), "Message deleted by author")
    }

    func testDeletedMessageLocalizationModeratorIsDeleter() throws {
        let (message, parent) = deletedMessage(authorId: "alice", authorType: "users", deleterId: "bob", deleterType: "users", deleterName: "Bob")

        let localizedMessage = NCSystemMessageLocalizer.localizedDeletedMessage(for: message, withParent: parent, account: account)
        XCTAssertEqual(localizedMessage, "Message deleted by {actor}")
        XCTAssertEqual(parsedDeletedMessage(for: parent, withLocalizedMessage: localizedMessage), "Message deleted by @Bob")
    }

    func testDeletedMessageLocalizationGuestIsDeleter() throws {
        let (message, parent) = deletedMessage(authorId: "alice", authorType: "users", deleterId: "guestSessionHash", deleterType: "guests", deleterName: "Guest user")

        let localizedMessage = NCSystemMessageLocalizer.localizedDeletedMessage(for: message, withParent: parent, account: account)
        XCTAssertEqual(localizedMessage, "Message deleted by {actor}")
        XCTAssertEqual(parsedDeletedMessage(for: parent, withLocalizedMessage: localizedMessage), "Message deleted by @Guest user")
    }
}
