//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

// The Olm operations the call key exchange needs, implemented with vodozemac in CallEncryptionVodozemac.swift.
// Keys and ciphertexts are unpadded base64 like on the wire. Only used from the CallEncryption queue.

struct OlmMessage {
    // The raw values are the message types sent to the web client
    enum Kind: Int {
        case preKey = 0
        case normal = 1
    }

    let kind: Kind
    let body: String
}

protocol OlmAccountProtocol: AnyObject {
    // Curve25519
    var identityKey: String { get }

    // Creates a one-time key and marks it as published
    func createOneTimeKey() -> String?

    func createOutboundSession(theirIdentityKey: String, theirOneTimeKey: String) throws -> OlmSessionProtocol

    // Also decrypts the message and consumes the one-time key it used, vodozemac cannot decrypt it again afterwards
    func createInboundSession(preKeyMessage: OlmMessage) throws -> (session: OlmSessionProtocol, plaintext: String)
}

protocol OlmSessionProtocol: AnyObject {
    func encrypt(_ plaintext: String) throws -> OlmMessage
    func decrypt(_ message: OlmMessage) throws -> String
}
