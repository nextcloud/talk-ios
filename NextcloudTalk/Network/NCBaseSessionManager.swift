//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class NCBaseSessionManager: NSObject {

    public typealias SuccessBlock = (_ task: URLSessionDataTask, _ responseObject: Any?) -> Void
    public typealias FailureBlock = (_ task: URLSessionDataTask?, _ error: Error) -> Void

    public let session: URLSession
    public var userAgent: String = NCAppBranding.userAgent()

    // When not set, the timeout of the session configuration applies
    public var timeoutInterval: TimeInterval?

    private let responseType: NCHTTPSerialization.ResponseType
    private let headers = ThreadSafeDictionary<String, String>()

    init(configuration: URLSessionConfiguration, responseType: NCHTTPSerialization.ResponseType) {
        self.responseType = responseType

        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1

        // The session retains its delegate, so it must not be the manager itself, or the manager would never be released
        self.session = URLSession(configuration: configuration, delegate: NCSessionDelegate(), delegateQueue: delegateQueue)

        super.init()

        self.updateUserAgent()
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    internal func updateUserAgent() {
        self.setValue(self.userAgent, forHTTPHeaderField: "User-Agent")
    }

    // MARK: - Headers

    public func setValue(_ value: String?, forHTTPHeaderField field: String) {
        headers[field] = value
    }

    public func value(forHTTPHeaderField field: String) -> String? {
        return headers[field]
    }

    // MARK: - Requests

    public func request(withMethod method: String, urlString: String, parameters: Any?) -> URLRequest? {
        return NCHTTPSerialization.request(withMethod: method, urlString: urlString, parameters: parameters, headers: headers.dictionary, timeoutInterval: timeoutInterval)
    }

    // The completion handler is called on the main queue, the returned task is not resumed yet
    public func dataTask(with request: URLRequest, completionHandler: @escaping (_ response: URLResponse?, _ responseObject: Any?, _ error: Error?) -> Void) -> URLSessionDataTask {
        let responseType = self.responseType

        return session.dataTask(with: request) { data, response, error in
            if let error {
                DispatchQueue.main.async {
                    completionHandler(response, nil, error)
                }

                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let (responseObject, responseError) = NCHTTPSerialization.responseObject(for: response, data: data, type: responseType)

                DispatchQueue.main.async {
                    completionHandler(response, responseObject, responseError)
                }
            }
        }
    }

    @discardableResult
    public func get(_ URLString: String, parameters: Any?, success: SuccessBlock?, failure: FailureBlock?) -> URLSessionDataTask? {
        return resumedDataTask(withMethod: "GET", urlString: URLString, parameters: parameters, success: success, failure: failure)
    }

    @discardableResult
    public func post(_ URLString: String, parameters: Any?, success: SuccessBlock?, failure: FailureBlock?) -> URLSessionDataTask? {
        return resumedDataTask(withMethod: "POST", urlString: URLString, parameters: parameters, success: success, failure: failure)
    }

    @discardableResult
    public func put(_ URLString: String, parameters: Any?, success: SuccessBlock?, failure: FailureBlock?) -> URLSessionDataTask? {
        return resumedDataTask(withMethod: "PUT", urlString: URLString, parameters: parameters, success: success, failure: failure)
    }

    @discardableResult
    public func delete(_ URLString: String, parameters: Any?, success: SuccessBlock?, failure: FailureBlock?) -> URLSessionDataTask? {
        return resumedDataTask(withMethod: "DELETE", urlString: URLString, parameters: parameters, success: success, failure: failure)
    }

    @discardableResult
    public func post(_ URLString: String, constructingBodyWith block: (NCMultipartFormData) -> Void, success: SuccessBlock?, failure: FailureBlock?) -> URLSessionDataTask? {
        guard var request = self.request(withMethod: "POST", urlString: URLString, parameters: nil) else {
            return failForInvalidURL(URLString, failure: failure)
        }

        let formData = NCMultipartFormData()
        block(formData)

        request.setValue(formData.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = formData.body

        return resumedDataTask(with: request, success: success, failure: failure)
    }

    private func resumedDataTask(withMethod method: String, urlString: String, parameters: Any?, success: SuccessBlock?, failure: FailureBlock?) -> URLSessionDataTask? {
        guard let request = self.request(withMethod: method, urlString: urlString, parameters: parameters) else {
            return failForInvalidURL(urlString, failure: failure)
        }

        return resumedDataTask(with: request, success: success, failure: failure)
    }

    private func resumedDataTask(with request: URLRequest, success: SuccessBlock?, failure: FailureBlock?) -> URLSessionDataTask {
        var task: URLSessionDataTask!

        task = self.dataTask(with: request) { _, responseObject, error in
            if let error {
                failure?(task, error)
            } else {
                success?(task, responseObject)
            }
        }

        task.resume()

        return task
    }

    private func failForInvalidURL(_ urlString: String, failure: FailureBlock?) -> URLSessionDataTask? {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadURL, userInfo: [NSURLErrorFailingURLStringErrorKey: urlString])

        DispatchQueue.main.async {
            failure?(nil, error)
        }

        return nil
    }
}

private final class NCSessionDelegate: NSObject, URLSessionDelegate {

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // The pinning check
        if CCCertificate.sharedManager().checkTrustedChallenge(challenge), let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
