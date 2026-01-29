//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

extension Dictionary where Key == String, Value == NCMessageParameter {

    static func fromJSONString(_ jsonString: String) -> [String: NCMessageParameter]? {
        guard let jsonData = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: [String: Any]]
        else { return nil }

        var result: [String: NCMessageParameter] = [:]

        for (key, value) in dict {
            result[key] = NCMessageParameter(dictionary: value)
        }

        return result
    }

    func asDictionary() -> [String: [String: Any]] {
        var result: [String: [String: Any]] = [:]

        for (key, value) in self {
            result[key] = value.asDictionary()
        }

        return result
    }

    func asJSONString() -> String? {
        let dict = self.asDictionary()

        if let jsonData = try? JSONSerialization.data(withJSONObject: dict),
           let jsonString = String(data: jsonData, encoding: .utf8) {

            return jsonString
        }

        return nil
    }
}

@objcMembers
public class NCMessageParameter: NSObject {

    public var parameterId: String
    public var name: String
    public var type: String
    public var link: String?

    // Can't be an optional when accessed via ObjC
    // TODO: Should get rid of the range parameter
    public var range = NSRange()
    public var contactName: String?
    public var contactPhoto: String?
    public var mention: Mention?

    init(parameterId: String, name: String, type: String) {
        self.parameterId = parameterId
        self.name = name
        self.type = type
    }

    init?(dictionary dict: [String: Any]?) {
        guard let dict else { return nil }

        if let intId = dict["id"] as? Int {
            self.parameterId = String(intId)
        } else {
            self.parameterId = dict["id"] as? String ?? ""
        }

        self.name = dict["name"] as? String ?? ""
        self.type = dict["type"] as? String ?? ""
        self.link = dict["link"] as? String
        self.contactName = dict["contact-name"] as? String
        self.contactPhoto = dict["contact-photo"] as? String

        super.init()

        if self.isMention {
            let mentionDisplayName = dict["mention-display-name"] as? String ?? self.name
            let mentionId = dict["mention-id"] as? String

            self.mention = Mention(id: self.parameterId, label: mentionDisplayName, mentionId: mentionId)
        }
    }

    public var isMention: Bool {
        return type == "user" || type == "guest" || type == "user-group" ||
                type == "call" || type == "email" || type == "circle"
    }

    public var shouldBeHighlighted: Bool {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        // Own mention
        if type == "user" {
            return activeAccount.userId == parameterId
        }

        // Group mention
        if type == "user-group" {
            let userGroup = activeAccount.groupIds.value(forKey: "self") as? [String] ?? []

            if let mention {
                return userGroup.contains(mention.id)
            }
        }

        // Team mention
        if type == "circle" {
            let userTeams = activeAccount.teamIds.value(forKey: "self") as? [String] ?? []

            if let mention {
                return userTeams.contains(mention.id)
            }
        }

        // Call mention
        return (type == "call")
    }

    public var contactPhotoImage: UIImage? {
        guard let contactPhoto,
              let imageUrl = URL(string: "data:image/png;base64,\(contactPhoto)"),
              let imageData = try? Data(contentsOf: imageUrl)
        else { return nil }

        return UIImage(data: imageData)
    }

    public func asDictionary() -> [String: Any] {
        var result: [String: Any?] = [
            "id": self.parameterId,
            "name": self.name,
            "link": self.link,
            "type": self.type,
            "contact-name": self.contactName,
            "contact-photo": self.contactPhoto,
            "mention-id": self.mention?.mentionId,
            "mention-display-name": self.mention?.label
        ]

        return result.compactMapValues { $0 }
    }
}
