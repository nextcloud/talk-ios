//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class Mention: NSObject {

    public var id: String
    public var label: String
    public var mentionId: String?

    init(id: String, label: String) {
        self.id = id
        self.label = label
    }

    init(id: String, label: String, mentionId: String? = nil) {
        self.id = id
        self.label = label
        self.mentionId = mentionId
    }

    public var idForChat: String {
        // Prefer mentionId if it's supported by the server
        let id = self.mentionId ?? self.id

        return "@\"\(id)\""
    }

    public var labelForChat: String {
        return "@\(label)"
    }
}
