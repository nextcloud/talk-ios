//
// Copyright (c) 2024 Marcel Müller <marcel-mueller@gmx.de>
//
// Author Ivan Sein <ivan@nextcloud.com>
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
