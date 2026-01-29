//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers class BGTaskHelper: NSObject {

#if !APP_EXTENSION
    var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
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

    public func stopBackgroundTask() {
#if !APP_EXTENSION
        if backgroundTaskIdentifier != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = .invalid
        }
#endif
    }

}
