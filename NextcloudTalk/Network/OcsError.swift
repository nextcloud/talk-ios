//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class OcsError: NSObject, CustomNSError {

    let error: NSError
    let task: URLSessionDataTask?

    lazy var responseDict: [String: AnyObject]? = {
        guard let errorData = error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey] as? Data,
              let errorDict = try? JSONSerialization.jsonObject(with: errorData) as? [AnyHashable: Any]
        else { return nil }

        return errorDict as? [String: AnyObject]
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

    lazy var errorKey: String? = {
        return dataDict?["error"] as? String
    }()

    lazy var errorMessage: String? = {
        return dataDict?["message"] as? String
    }()

    // Implement CustomNSError to acces this class from ObjC as well
    public var errorUserInfo: [String: Any] {
        return [ "ocsError": self ]
    }

    public override var description: String {
        return error.description
    }

    init(withError error: NSError, withTask task: URLSessionDataTask?) {
        self.error = error
        self.task = task
    }
}
