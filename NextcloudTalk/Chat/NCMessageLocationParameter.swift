//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

@objcMembers
public class NCMessageLocationParameter: NCMessageParameter {

    public var latitude: String?
    public var longitude: String?

    override init?(dictionary dict: [String: Any]?) {
        super.init(dictionary: dict)

        self.latitude = dict?["latitude"] as? String
        self.longitude = dict?["longitude"] as? String
    }

}
