//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import CommonCrypto
import UICKeyChainStore

let kNCNormalPushTokenKey = "ncNormalPushToken"
let kNCPushKitTokenKey = "ncPushKitToken"

class NCKeyChainController: NSObject {

    private static let tokenKey = "ncToken"
    private static let pushNotificationPublicKey = "ncPNPublicKey"
    private static let pushNotificationPrivateKey = "ncPNPrivateKey"

    private static let shared = NCKeyChainController()

    static func sharedInstance() -> NCKeyChainController {
        return shared
    }

    private let keychain = UICKeyChainStore(service: bundleIdentifier, accessGroup: groupIdentifier)

    func setToken(_ token: String, forAccountId accountId: String) {
        keychain.setString(token, forKey: "\(NCKeyChainController.tokenKey)-\(accountId)")
    }

    func token(forAccountId accountId: String) -> String? {
        return keychain.string(forKey: "\(NCKeyChainController.tokenKey)-\(accountId)")
    }

    func setPushNotificationPublicKey(_ publicKey: Data, forAccountId accountId: String) {
        keychain.setData(publicKey, forKey: "\(NCKeyChainController.pushNotificationPublicKey)-\(accountId)")
    }

    func pushNotificationPublicKey(forAccountId accountId: String) -> Data? {
        return keychain.data(forKey: "\(NCKeyChainController.pushNotificationPublicKey)-\(accountId)")
    }

    func setPushNotificationPrivateKey(_ privateKey: Data, forAccountId accountId: String) {
        keychain.setData(privateKey, forKey: "\(NCKeyChainController.pushNotificationPrivateKey)-\(accountId)")
    }

    func pushNotificationPrivateKey(forAccountId accountId: String) -> Data? {
        return keychain.data(forKey: "\(NCKeyChainController.pushNotificationPrivateKey)-\(accountId)")
    }

    // Empty when no push token is stored, which is what the server received before as well
    func pushTokenSHA512() -> String {
        guard let token = combinedPushToken() else { return "" }

        return sha512(token)
    }

    func logCombinedPushToken() {
        let normalPushToken = keychain.string(forKey: kNCNormalPushTokenKey) ?? ""
        let pushKitToken = keychain.string(forKey: kNCPushKitTokenKey) ?? ""

        if normalPushToken.count >= 10 {
            NCLog.log("Push notification, normal push token: \(normalPushToken.prefix(10))... length \(normalPushToken.count)")
        } else {
            NCLog.log("Push notification, normal push token length < 10")
        }

        if pushKitToken.count >= 10 {
            NCLog.log("Push notification, pushKit token: \(pushKitToken.prefix(10))... length \(pushKitToken.count)")
        } else {
            NCLog.log("Push notification, pushKit token length < 10")
        }
    }

    func combinedPushToken() -> String? {
        guard let normalPushToken = keychain.string(forKey: kNCNormalPushTokenKey),
              let pushKitToken = keychain.string(forKey: kNCPushKitTokenKey)
        else { return nil }

        if NCUtils.isiOSAppOnMac() {
            // As CallKit is not supported on MacOS, we only supply the
            // normal push token, to generate local notifications for calls
            return normalPushToken
        }

        return "\(normalPushToken) \(pushKitToken)"
    }

    func removeAllItems() {
        UICKeyChainStore.removeAllItems(forService: bundleIdentifier, accessGroup: groupIdentifier)
    }

    private func sha512(_ string: String) -> String {
        let data = Data(string.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA512($0.baseAddress, CC_LONG(data.count), &digest)
        }

        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
