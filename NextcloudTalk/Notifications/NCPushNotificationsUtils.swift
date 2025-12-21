//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftyRSA

@objcMembers
public class NCPushNotificationsUtils: NSObject {

    public static func decryptPushNotification(message: String, withDevicePrivateKey key: NSData) -> String? {
        do {
            let privateKey = try PrivateKey(pemEncoded: String(data: key as Data, encoding: .utf8)!)
            let encryptedMessage = try EncryptedMessage(base64Encoded: message)
            let clearMessage = try encryptedMessage.decrypted(with: privateKey, padding: .PKCS1)

            return try clearMessage.string(encoding: .utf8)
        } catch {
            print("decryptPushNotificationError: \(error)")
        }

        return nil
    }

    public static func generatePushNotificationKeyPair() -> NCPushNotificationKeyPair? {
        do {
            let keyPair = try SwiftyRSA.generateRSAKeyPair(sizeInBits: 2048)

            let privateKey = try keyPair.privateKey.data().prependx509Header().base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
            let publicKey = try keyPair.publicKey.data().prependx509Header().base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])

            let privateKeyPem = "-----BEGIN PRIVATE KEY-----\n\(privateKey)\n-----END PRIVATE KEY-----"
            let publicKeyPem = "-----BEGIN PUBLIC KEY-----\n\(publicKey)\n-----END PUBLIC KEY-----"

            return NCPushNotificationKeyPair(privateKey: privateKeyPem.data(using: .utf8)!, publicKey: publicKeyPem.data(using: .utf8)!)
        } catch {
            NCUtils.log("Error generating push keypair: \(error)")
        }

        return nil
    }

}
