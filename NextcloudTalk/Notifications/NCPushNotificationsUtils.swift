//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftyRSA

@objcMembers
public class NCPushNotificationsUtils: NSObject {

    public static func decryptPushNotification(withMessageBase64 messageBase64: String, withSignatureBase64 signatureBase64: String, forAccount account: TalkAccount) -> String? {
        do {
            guard let userPublicKeyPem = account.userPublicKey else { return nil }

            let encryptedMessage = try EncryptedMessage(base64Encoded: messageBase64)
            let userPublicKey = try RsaPublicKey(pemEncoded: userPublicKeyPem)
            let signature = try Signature(base64Encoded: signatureBase64)

            guard try encryptedMessage.verify(with: userPublicKey, signature: signature, digestType: .sha512) else {
                return nil
            }

            guard let devicePrivateKeyData = NCKeyChainController.sharedInstance().pushNotificationPrivateKey(forAccountId: account.accountId),
                  let devicePrivateKeyPem = String(data: devicePrivateKeyData, encoding: .utf8) else {
                return nil
            }

            let devicePrivateKey = try RsaPrivateKey(pemEncoded: devicePrivateKeyPem)
            let clearMessage = try encryptedMessage.decrypted(with: devicePrivateKey, padding: .PKCS1)

            return try clearMessage.string(encoding: .utf8)
        } catch {
            print("decryptPushNotificationError: \(error)")
        }

        return nil
    }

    public static func generatePushNotificationKeyPair() -> NCPushNotificationKeyPair? {
        do {
            let keyPair = try SwiftyRSA.generateRSAKeyPair(sizeInBits: 2048)

            let privateKeyPem = try keyPair.privateKey.pemStringPkcs8()
            let publicKeyPem = try keyPair.publicKey.pemStringPkcs8()

            return NCPushNotificationKeyPair(privateKey: privateKeyPem.data(using: .utf8)!, publicKey: publicKeyPem.data(using: .utf8)!)
        } catch {
            NCUtils.log("Error generating push keypair: \(error)")
        }

        return nil
    }

}
