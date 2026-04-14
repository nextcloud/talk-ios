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

    private lazy var response: HTTPURLResponse? = {
        guard let response = task?.response,
              let httpResponse = response as? HTTPURLResponse
        else { return nil }

        return httpResponse
    }()

    lazy var responseStatusCode: Int = {
        return response?.statusCode ?? 0
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

    func value(forHTTPHeaderField field: String) -> String? {
        return response?.value(forHTTPHeaderField: field)
    }

    init(withData data: Any?, withTask task: URLSessionDataTask?) {
        self.data = data
        self.task = task
    }
}
