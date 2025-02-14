//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class NCCalDAVSessionManager: NCBaseSessionManager {

    init(configuration: URLSessionConfiguration) {
        super.init(configuration: configuration, responseSerializer: AFHTTPResponseSerializer(), requestSerializer: AFHTTPRequestSerializer())

        self.responseSerializer.acceptableContentTypes?.insert("application/xml")
        self.responseSerializer.acceptableContentTypes?.insert("text/xml")
    }

}
