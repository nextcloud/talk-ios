//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

let kParticipantTypeUser = "users"
let kParticipantTypeGroup = "groups"
let kParticipantTypeEmail = "emails"
let kParticipantTypeCircle = "circles"
let kParticipantTypeFederated = "federated_users"

@objcMembers class NCUser: NSObject {

    var userId = ""
    var name = ""
    var source = ""

    override init() {
        super.init()
    }

    init?(dictionary: [String: Any]?) {
        guard let dictionary else { return nil }

        self.userId = NCUser.stringValue(dictionary["id"])
        self.name = NCUser.stringValue(dictionary["label"])
        self.source = NCUser.stringValue(dictionary["source"])

        if self.source == "remotes" {
            self.source = kParticipantTypeFederated
        }

        super.init()
    }

    static func userFromNCContact(_ contact: NCContact) -> NCUser {
        let user = NCUser()
        user.name = contact.name() ?? ""
        user.userId = contact.userId() ?? ""
        user.source = kParticipantTypeUser
        return user
    }

    static func indexedUsers(fromUsersArray users: [NCUser]) -> [String: [NCUser]] {
        var indexedUsers: [String: [NCUser]] = [:]

        for user in users {
            var index = "#"

            if let first = user.name.first, first.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) {
                index = String(first).uppercased()
            }

            indexedUsers[index, default: []].append(user)
        }

        return indexedUsers
    }

    // Users of the second array that are already part of the first array are dropped
    static func combineUsersArray(_ firstArray: [NCUser], withUsersArray secondArray: [NCUser]) -> [NCUser] {
        let filteredSecondArray = secondArray.filter { secondArrayUser in
            secondArrayUser.source != kParticipantTypeUser || !firstArray.contains { $0.userId == secondArrayUser.userId }
        }

        return firstArray + filteredSecondArray
    }

    private static func stringValue(_ value: Any?) -> String {
        if let string = value as? String {
            return string
        }

        return (value as? NSNumber)?.stringValue ?? ""
    }
}
