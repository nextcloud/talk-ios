//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class NCBaseSessionManager: AFHTTPSessionManager {

    public static var baseUserAgent = "Mozilla/5.0 (iOS) Nextcloud-Talk v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "Unknown")"
    public var userAgent: String = baseUserAgent

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
}
