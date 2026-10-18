//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

public struct PushDeviceRegistration {
    let deviceIdentifier: String
    let signature: String
    let userPublicKey: String

    init?(dataDict: [String: Any]?) {
        guard let deviceIdentifier = dataDict?["deviceIdentifier"] as? String,
              let signature = dataDict?["signature"] as? String,
              let userPublicKey = dataDict?["publicKey"] as? String
        else { return nil }

        self.deviceIdentifier = deviceIdentifier
        self.signature = signature
        self.userPublicKey = userPublicKey
    }

    init?(account: TalkAccount) {
        // deviceIdentifier and deviceSignature are declared nonnull but are nil until the first subscription, which bridges to ""
        let deviceIdentifier: String = account.deviceIdentifier
        let signature: String = account.deviceSignature

        guard !deviceIdentifier.isEmpty, !signature.isEmpty,
              let userPublicKey = account.userPublicKey
        else { return nil }

        self.deviceIdentifier = deviceIdentifier
        self.signature = signature
        self.userPublicKey = userPublicKey
    }

    func apply(to account: TalkAccount) {
        account.deviceIdentifier = deviceIdentifier
        account.deviceSignature = signature
        account.userPublicKey = userPublicKey
    }
}
