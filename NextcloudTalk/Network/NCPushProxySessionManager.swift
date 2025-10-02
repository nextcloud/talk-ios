//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class NCPushProxySessionManager: NCBaseSessionManager {

    public static let shared = NCPushProxySessionManager()

    init() {
        let configuration = URLSessionConfiguration.default
        super.init(configuration: configuration, responseSerializer: AFHTTPResponseSerializer(), requestSerializer: AFHTTPRequestSerializer())

        self.userAgent += " (Strict VoIP)"
        self.updateUserAgent()

        // As we can run max. 30s in the background, we need to lower the default timeout from 60s to something < 30s.
        // Otherwise our app can be killed when trying to register while in the background
        self.requestSerializer.timeoutInterval = 25
    }

}
