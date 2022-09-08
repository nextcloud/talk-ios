//
// Copyright (c) 2022 Marcel Müller <marcel-mueller@gmx.de>
//
// Author Marcel Müller <marcel-mueller@gmx.de>
//
// GNU GPL version 3 or any later version
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation

@objcMembers class BGTaskHelper: NSObject {

    var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid

    public class func startBackgroundTask(withName taskName: String? = nil, expirationHandler handler: ((BGTaskHelper) -> Void)? = nil) -> BGTaskHelper {
        let taskHelper = BGTaskHelper()

        let expirationhandler = {
            if let handler = handler {
                handler(taskHelper)
            }
        }

        let backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: taskName, expirationHandler: expirationhandler)
        taskHelper.backgroundTaskIdentifier = backgroundTaskIdentifier

        return taskHelper
    }

    public func stopBackgroundTask() {
        if backgroundTaskIdentifier != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = .invalid
        }
    }

}
