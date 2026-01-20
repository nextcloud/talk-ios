//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

extension Dictionary where Key == String, Value == Any {

    subscript(intForKey key: String) -> Int? {
        let value = self[key]

        if let intValue = value as? Int {
            return intValue
        } else if let stringValue = value as? String {
            return Int(stringValue)
        }

        return nil
    }

}
