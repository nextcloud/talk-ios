//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import TalkOlm

final class VodozemacOlmAccount: OlmAccountProtocol {

    let identityKey: String

    private let account = VodozemacAccount()

    init() {
        identityKey = account.identityKey()
    }

    func createOneTimeKey() -> String? {
        return try? account.createOneTimeKey()
    }

    func createOutboundSession(theirIdentityKey: String, theirOneTimeKey: String) throws -> OlmSessionProtocol {
        let session = try account.createOutboundSession(theirIdentityKey: theirIdentityKey, theirOneTimeKey: theirOneTimeKey)
        return VodozemacOlmSession(session)
    }

    func createInboundSession(preKeyMessage: OlmMessage) throws -> (session: OlmSessionProtocol, plaintext: String) {
        let inbound = try account.createInboundSession(preKeyMessage: VodozemacMessage(preKeyMessage))
        return (VodozemacOlmSession(inbound.session), inbound.plaintext)
    }
}

final class VodozemacOlmSession: OlmSessionProtocol {

    private let session: VodozemacSession

    init(_ session: VodozemacSession) {
        self.session = session
    }

    func encrypt(_ plaintext: String) throws -> OlmMessage {
        return OlmMessage(try session.encrypt(plaintext: plaintext))
    }

    func decrypt(_ message: OlmMessage) throws -> String {
        return try session.decrypt(message: VodozemacMessage(message))
    }
}

private extension VodozemacMessage {
    init(_ message: OlmMessage) {
        switch message.kind {
        case .preKey:
            self.init(kind: .preKey, body: message.body)
        case .normal:
            self.init(kind: .normal, body: message.body)
        }
    }
}

private extension OlmMessage {
    init(_ message: VodozemacMessage) {
        switch message.kind {
        case .preKey:
            self.init(kind: .preKey, body: message.body)
        case .normal:
            self.init(kind: .normal, body: message.body)
        }
    }
}
