//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers class BGTaskHelper: NSObject {

#if !APP_EXTENSION
    var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
#else
    private let activitySemaphore = DispatchSemaphore(value: 0)
#endif

    public var isExpired: Bool = false

    public class func startBackgroundTask(withName taskName: String? = #function, expirationHandler handler: ((BGTaskHelper) -> Void)? = nil) -> BGTaskHelper {
        let taskHelper = BGTaskHelper()

        let expirationhandler = {
            taskHelper.isExpired = true

            if let handler = handler {
                handler(taskHelper)
            }
        }

#if !APP_EXTENSION
        let backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: taskName, expirationHandler: expirationhandler)
        taskHelper.backgroundTaskIdentifier = backgroundTaskIdentifier
#endif

        return taskHelper
    }

    /// Like `startBackgroundTask`, but in app extensions it asks for time as well. There it keeps a thread
    /// waiting until the task is stopped, and the expiration handler is not called on the main thread.
    public class func startExpiringActivity(withName taskName: String, expirationHandler handler: ((BGTaskHelper) -> Void)? = nil) -> BGTaskHelper {
#if APP_EXTENSION
        let taskHelper = BGTaskHelper()

        ProcessInfo.processInfo.performExpiringActivity(withReason: taskName) { expired in
            guard expired else {
                // The activity lasts as long as this block runs
                taskHelper.activitySemaphore.wait()
                return
            }

            taskHelper.isExpired = true
            handler?(taskHelper)
            taskHelper.activitySemaphore.signal()
        }

        return taskHelper
#else
        return self.startBackgroundTask(withName: taskName, expirationHandler: handler)
#endif
    }

    public func stopBackgroundTask() {
#if !APP_EXTENSION
        if backgroundTaskIdentifier != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = .invalid
        }
#else
        activitySemaphore.signal()
#endif
    }

}
