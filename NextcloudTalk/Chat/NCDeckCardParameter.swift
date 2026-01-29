//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

@objcMembers
public class NCDeckCardParameter: NCMessageParameter {

    public var stackName: String?
    public var boardName: String?

    override init?(dictionary dict: [String: Any]?) {
        super.init(dictionary: dict)

        self.stackName = dict?["stackname"] as? String
        self.boardName = dict?["boardname"] as? String
    }

}
