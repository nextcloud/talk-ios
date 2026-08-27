//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class NCBaseSessionManager: AFHTTPSessionManager, NSDiscardableContent {

    public var userAgent: String = NCAppBranding.userAgent()

    init(configuration: URLSessionConfiguration, responseSerializer: AFHTTPResponseSerializer, requestSerializer: AFHTTPRequestSerializer) {
        super.init(baseURL: nil, sessionConfiguration: configuration)

        self.responseSerializer = responseSerializer
        self.requestSerializer = requestSerializer

        self.securityPolicy = AFSecurityPolicy(pinningMode: .none)

        self.updateUserAgent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    internal func updateUserAgent() {
        self.requestSerializer.setValue(self.userAgent, forHTTPHeaderField: "User-Agent")
    }

    public override func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // The pinning check
        if CCCertificate.sharedManager().checkTrustedChallenge(challenge) {
            completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    public func beginContentAccess() -> Bool {
        return true
    }

    public func endContentAccess() {
    }

    public func discardContentIfPossible() {
    }

    public func isContentDiscarded() -> Bool {
        // Return false to not get evicated from NSCache when moving to background
        return false
    }
}
