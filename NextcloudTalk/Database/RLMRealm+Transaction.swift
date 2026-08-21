//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

extension RLMRealm {

    /// Runs `block` in a write transaction on the current thread's default realm.
    ///
    /// The transaction is wrapped in a background task, so iOS does not suspend us while the realm
    /// write lock is held, which would terminate the app.
    ///
    /// `name` defaults to the calling function and is used to name the background task and to report
    /// a failing transaction, so there's no need to pass it explicitly.
    @discardableResult
    static func writeTransaction<T>(_ name: String = #function, _ block: (RLMRealm) -> T) -> T? {
        let bgTask = BGTaskHelper.startBackgroundTask(withName: name)
        defer { bgTask.stopBackgroundTask() }

        let realm = RLMRealm.default()
        var result: T?

        do {
            try realm.transaction {
                result = block(realm)
            }
        } catch {
            NCLog.log("Realm write transaction failed in \(name): \(error.localizedDescription)")
            return nil
        }

        return result
    }
}
