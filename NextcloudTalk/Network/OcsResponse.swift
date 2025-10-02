//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class OcsResponse: NSObject {

    let data: Any?
    let task: URLSessionDataTask?

    lazy var responseDict: [String: AnyObject]? = {
        return data as? [String: AnyObject]
    }()

    lazy var responseStatusCode: Int = {
        guard let response = task?.response,
              let httpResponse = response as? HTTPURLResponse
        else { return 0 }

        return httpResponse.statusCode
    }()

    lazy var ocsDict: [String: AnyObject]? = {
        return responseDict?["ocs"] as? [String: AnyObject]
    }()

    lazy var dataDict: [String: AnyObject]? = {
        return ocsDict?["data"] as? [String: AnyObject]
    }()

    lazy var dataArrayDict: [[String: AnyObject]]? = {
        return ocsDict?["data"] as? [[String: AnyObject]]
    }()

    init(withData data: Any?, withTask task: URLSessionDataTask?) {
        self.data = data
        self.task = task
    }
}
