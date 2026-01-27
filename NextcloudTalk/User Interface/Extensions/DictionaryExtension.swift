//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

extension Dictionary where Key == AnyHashable, Value == Any {

    subscript(intForKey key: AnyHashable) -> Int? {
        let value = self[key]

        if let intValue = value as? Int {
            return intValue
        } else if let stringValue = value as? String {
            return Int(stringValue)
        }

        return nil
    }

    subscript(boolForKey key: AnyHashable) -> Bool? {
        let value = self[key]

        if let boolValue = value as? Bool {
            return boolValue
        } else if let stringValue = value as? String {
            return Bool(stringValue)
        }

        return nil
    }

    subscript(stringForKey key: AnyHashable) -> String? {
        let value = self[key]

        if let stringValue = value as? String {
            return stringValue
        }

        return nil
    }

}

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

    subscript(boolForKey key: String) -> Bool? {
        let value = self[key]

        if let boolValue = value as? Bool {
            return boolValue
        } else if let stringValue = value as? String {
            return Bool(stringValue)
        }

        return nil
    }

    subscript(stringForKey key: String) -> String? {
        let value = self[key]

        if let stringValue = value as? String {
            return stringValue
        }

        return nil
    }

}
