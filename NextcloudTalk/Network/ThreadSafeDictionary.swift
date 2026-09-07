//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// NSCache is thread safe as well, but it evicts when the app moves to the background, which loses the
/// identity of values that callers keep a reference to. Ref https://github.com/nextcloud/spreed/issues/19197
class ThreadSafeDictionary<Key: Hashable, Value> {

    private var storage = [Key: Value]()
    private let lock = NSLock()

    subscript(key: Key) -> Value? {
        get {
            self.lock.lock()
            defer { self.lock.unlock() }

            return self.storage[key]
        }

        set {
            self.lock.lock()
            defer { self.lock.unlock() }

            self.storage[key] = newValue
        }
    }

    /// The first stored value wins, so callers racing on a key all end up with the same instance
    @discardableResult
    func setIfAbsent(_ value: Value, forKey key: Key) -> Value {
        self.lock.lock()
        defer { self.lock.unlock() }

        if let existingValue = self.storage[key] {
            return existingValue
        }

        self.storage[key] = value

        return value
    }

    func removeValue(forKey key: Key) {
        self.lock.lock()
        defer { self.lock.unlock() }

        self.storage.removeValue(forKey: key)
    }
}
