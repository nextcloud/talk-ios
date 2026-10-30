//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitCCCertificateTest: XCTestCase {

    // Self-signed certificates for cert-a.invalid and cert-b.invalid
    private let certificateA = Data(base64Encoded: "MIIBiTCCAS+gAwIBAgIUa2LPCJqcqwry8zE6eaiKvkqAZVcwCgYIKoZIzj0EAwIwGTEXMBUGA1UEAwwOY2VydC1hLmludmFsaWQwIBcNMjYxMDMwMDkzNDU3WhgPMjEyNjEwMDYwOTM0NTdaMBkxFzAVBgNVBAMMDmNlcnQtYS5pbnZhbGlkMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEGT0owUBm8qCxott0v4iPQ54asQ2MMqBdWtmmWKVUWcCMoZCTkfIz3/rVr3UmcYDtD9LXz3BRwoPCt3vsqDmKl6NTMFEwHQYDVR0OBBYEFL1+Xp63fYrq1fk3CbnIhv5dIGfyMB8GA1UdIwQYMBaAFL1+Xp63fYrq1fk3CbnIhv5dIGfyMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDSAAwRQIhAN4Cxjlg0QptBiib/+hFml06qXxmeqD7ym8pmU0D5AWfAiA1ULXT+pmj4ONG2c3PKWEVoSlwPgpZUpPnhJmeQVpTgg==")!
    private let certificateB = Data(base64Encoded: "MIIBiTCCAS+gAwIBAgIUV9HPpVe33bADZ/kuD2S4UgQkquIwCgYIKoZIzj0EAwIwGTEXMBUGA1UEAwwOY2VydC1iLmludmFsaWQwIBcNMjYxMDMwMDkzNDU3WhgPMjEyNjEwMDYwOTM0NTdaMBkxFzAVBgNVBAMMDmNlcnQtYi5pbnZhbGlkMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEwOD+fDORuoay8tvdi/t85IJFuLNqflzQC3U6Hnwc1kJoxcT8pVwgG5JCSSOkdge/aS/jexuWRsYeBnWPVDyY0aNTMFEwHQYDVR0OBBYEFM12ykJFHLVETE44/4/48MigYBWRMB8GA1UdIwQYMBaAFM12ykJFHLVETE44/4/48MigYBWRMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDSAAwRQIhAIyw94deZV4wQTGc1VvA6Y2Lkf5nP5H48PGWvdvpyLt0AiB9TbnHDzRTmj/D8jtdHQmIZYJRtrMESvTB/5MFxboNvQ==")!

    // Unique per test, so certificates accepted by other runs or the app don't interfere
    private var hostA = ""
    private var hostB = ""

    override func setUp() {
        super.setUp()

        hostA = "a-\(UUID().uuidString.lowercased()).invalid"
        hostB = "b-\(UUID().uuidString.lowercased()).invalid"
    }

    override func tearDown() {
        let certificatesDirectory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)!
            .appendingPathComponent("Library/Application Support/Certificates")

        for host in [hostA, hostB] {
            try? FileManager.default.removeItem(at: certificatesDirectory.appendingPathComponent(NCUtils.sha256(fromString: host)))
        }

        super.tearDown()
    }

    func testAcceptedCertificateIsBoundToHost() throws {
        let manager = CCCertificate.sharedManager()!

        XCTAssertFalse(manager.checkTrustedChallenge(try challenge(host: hostA, certificate: certificateA)))

        XCTAssertTrue(manager.acceptCertificate(certificateA, forHost: hostA))

        XCTAssertTrue(manager.checkTrustedChallenge(try challenge(host: hostA, certificate: certificateA)))
        XCTAssertTrue(manager.checkTrustedChallenge(try challenge(host: hostA.uppercased(), certificate: certificateA)))
        XCTAssertFalse(manager.checkTrustedChallenge(try challenge(host: hostB, certificate: certificateA)))
        XCTAssertFalse(manager.checkTrustedChallenge(try challenge(host: hostA, certificate: certificateB)))
    }

    func testSameCertificateAcceptedForMultipleHosts() throws {
        let manager = CCCertificate.sharedManager()!

        XCTAssertTrue(manager.acceptCertificate(certificateA, forHost: hostA))
        XCTAssertFalse(manager.checkTrustedChallenge(try challenge(host: hostB, certificate: certificateA)))

        XCTAssertTrue(manager.acceptCertificate(certificateA, forHost: hostB))

        XCTAssertTrue(manager.checkTrustedChallenge(try challenge(host: hostA, certificate: certificateA)))
        XCTAssertTrue(manager.checkTrustedChallenge(try challenge(host: hostB, certificate: certificateA)))
    }

    func testNewCertificateReplacesPreviousOne() throws {
        let manager = CCCertificate.sharedManager()!

        XCTAssertTrue(manager.acceptCertificate(certificateA, forHost: hostA))
        XCTAssertTrue(manager.acceptCertificate(certificateB, forHost: hostA))

        XCTAssertTrue(manager.checkTrustedChallenge(try challenge(host: hostA, certificate: certificateB)))
        XCTAssertFalse(manager.checkTrustedChallenge(try challenge(host: hostA, certificate: certificateA)))
    }

    func testListAndRemoveAcceptedCertificates() throws {
        let manager = CCCertificate.sharedManager()!

        XCTAssertTrue(manager.acceptCertificate(certificateA, forHost: hostA))
        XCTAssertTrue(manager.acceptedCertificateHosts().contains(hostA))

        XCTAssertTrue(manager.removeAcceptedCertificate(forHost: hostA))

        XCTAssertFalse(manager.acceptedCertificateHosts().contains(hostA))
        XCTAssertFalse(manager.checkTrustedChallenge(try challenge(host: hostA, certificate: certificateA)))
    }

    // MARK: - Helpers

    private func challenge(host: String, certificate: Data) throws -> URLAuthenticationChallenge {
        let secCertificate = try XCTUnwrap(SecCertificateCreateWithData(nil, certificate as CFData))
        var trust: SecTrust?
        XCTAssertEqual(SecTrustCreateWithCertificates(secCertificate, SecPolicyCreateSSL(true, host as CFString), &trust), errSecSuccess)

        let protectionSpace = ServerTrustProtectionSpace(host: host, serverTrust: try XCTUnwrap(trust))

        return URLAuthenticationChallenge(protectionSpace: protectionSpace, proposedCredential: nil, previousFailureCount: 0, failureResponse: nil, error: nil, sender: ChallengeSender())
    }

    private final class ServerTrustProtectionSpace: URLProtectionSpace, @unchecked Sendable {
        private let trust: SecTrust

        init(host: String, serverTrust: SecTrust) {
            self.trust = serverTrust
            super.init(host: host, port: 443, protocol: NSURLProtectionSpaceHTTPS, realm: nil, authenticationMethod: NSURLAuthenticationMethodServerTrust)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var serverTrust: SecTrust? {
            return trust
        }
    }

    private final class ChallengeSender: NSObject, URLAuthenticationChallengeSender {
        func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
        func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
        func cancel(_ challenge: URLAuthenticationChallenge) {}
    }
}
