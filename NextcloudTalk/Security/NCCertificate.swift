//
// SPDX-FileCopyrightText: 2016 Marino Faggiana <m.faggiana@twsweb.it>, TWS
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import UIKit

protocol NCCertificateDelegate: AnyObject {
    func trustedCertificateAccepted()
    func trustedCertificateDenied()
}

extension NCCertificateDelegate {
    func trustedCertificateAccepted() {}
    func trustedCertificateDenied() {}
}

extension Notification.Name {
    // Posted on the main queue after a certificate was accepted, userInfo contains the host
    static let NCCertificateAccepted = Notification.Name(rawValue: "NCCertificateAcceptedNotification")
}

final class NCCertificate: NSObject {

    static let shared = NCCertificate()

    static let hostKey = "host"

    private static let certificatesFolder = "Library/Application Support/Certificates"

    // Stored next to the certificate of a host, as the directory name is a hash of the host
    private static let hostFileName = "host"
    private static let certificateFileName = "certificate.der"

    // Last untrusted certificate per host, offered when the user is asked to accept it
    private var pendingCertificates: [String: Data] = [:]
    private let pendingCertificatesLock = NSLock()

    private override init() {
        super.init()
        removeLegacyCertificates()
    }

    // MARK: - Trust evaluation

    func checkTrustedChallenge(_ challenge: URLAuthenticationChallenge) -> Bool {
        let protectionSpace = challenge.protectionSpace

        guard let trust = protectionSpace.serverTrust,
              let certificateData = leafCertificateData(of: trust),
              let hostDirectory = directory(forHost: protectionSpace.host)
        else { return false }

        let acceptedCertificateData = try? Data(contentsOf: hostDirectory.appendingPathComponent(Self.certificateFileName))

        if acceptedCertificateData == certificateData {
            NSLog("Certificated matched with one saved previously.")
            return true
        }

        pendingCertificatesLock.withLock {
            pendingCertificates[protectionSpace.host.lowercased()] = certificateData
        }

        return false
    }

    private func leafCertificateData(of trust: SecTrust) -> Data? {
        guard let leafCertificate = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else { return nil }

        return SecCertificateCopyData(leafCertificate) as Data
    }

    // MARK: - Alert

    func presentViewControllerCertificate(withError error: Error, viewController: UIViewController?, delegate: NCCertificateDelegate?) {
        guard let viewController else { return }

        // Only the certificate seen for the failed host is accepted, and only for that host
        let host = ((error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.host

        guard let host, let certificateData = pendingCertificatesLock.withLock({ pendingCertificates[host.lowercased()] }) else {
            NSLog("[LOG] Untrusted certificate error without certificate or host")
            return
        }

        var certificateChanged = false

        if let certificateURL = directory(forHost: host)?.appendingPathComponent(Self.certificateFileName) {
            certificateChanged = FileManager.default.fileExists(atPath: certificateURL.path)
        }

        var message = NSLocalizedString("Do you want to connect to the server anyway?", comment: "")

        if certificateChanged {
            message = NSLocalizedString("The certificate of this server has changed since you last accepted it. Do you want to connect to the server anyway?", comment: "")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak delegate] in
            let alertController = UIAlertController(title: error.localizedDescription, message: message, preferredStyle: .alert)

            alertController.addAction(UIAlertAction(title: NSLocalizedString("Yes", comment: ""), style: .default) { _ in
                if self.acceptCertificate(certificateData, forHost: host) {
                    // Other connections to this host may have failed too, but only one alert is shown
                    NotificationCenter.default.post(name: .NCCertificateAccepted, object: self, userInfo: [Self.hostKey: host])
                }

                delegate?.trustedCertificateAccepted()
            })

            alertController.addAction(UIAlertAction(title: NSLocalizedString("No", comment: ""), style: .cancel) { _ in
                delegate?.trustedCertificateDenied()
            })

            // Presenting from a view controller that already presents one (e.g. a call) silently fails
            var presentingViewController = viewController

            while let presented = presentingViewController.presentedViewController, !presented.isBeingDismissed {
                presentingViewController = presented
            }

            presentingViewController.present(alertController, animated: true)
        }
    }

    // MARK: - Accepted certificates

    @discardableResult
    func acceptCertificate(_ certificateData: Data, forHost host: String) -> Bool {
        guard let hostDirectory = directory(forHost: host) else { return false }

        let fileManager = FileManager.default

        // Replaces the certificate previously accepted for this host
        try? fileManager.removeItem(at: hostDirectory)

        do {
            try fileManager.createDirectory(at: hostDirectory, withIntermediateDirectories: true)
            try host.write(to: hostDirectory.appendingPathComponent(Self.hostFileName), atomically: true, encoding: .utf8)

            let certificateURL = hostDirectory.appendingPathComponent(Self.certificateFileName)
            NSLog("[LOG] currentCertLocation: %@", certificateURL.path)

            try certificateData.write(to: certificateURL, options: .atomic)
        } catch {
            NSLog("[LOG] Error: %@", error.localizedDescription)
            return false
        }

        return true
    }

    func acceptedCertificateHosts() -> [String] {
        guard let certificatesDirectory else { return [] }

        let directoryNames = (try? FileManager.default.contentsOfDirectory(atPath: certificatesDirectory.path)) ?? []

        let hosts = directoryNames.compactMap { directoryName -> String? in
            let hostFileURL = certificatesDirectory.appendingPathComponent(directoryName).appendingPathComponent(Self.hostFileName)
            guard let host = try? String(contentsOf: hostFileURL, encoding: .utf8), !host.isEmpty else { return nil }

            return host
        }

        return hosts.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func acceptedCertificateURL(forHost host: String) -> URL? {
        return directory(forHost: host)?.appendingPathComponent(Self.certificateFileName)
    }

    @discardableResult
    func removeAcceptedCertificate(forHost host: String) -> Bool {
        guard let hostDirectory = directory(forHost: host) else { return false }

        return (try? FileManager.default.removeItem(at: hostDirectory)) != nil
    }

    // MARK: - Storage

    private func directory(forHost host: String) -> URL? {
        guard !host.isEmpty else { return nil }

        // Hashed, as a host is not guaranteed to be a valid file name
        return certificatesDirectory?.appendingPathComponent(NCUtils.sha256(fromString: host.lowercased()))
    }

    // Certificates accepted before they were stored per host are no longer trusted
    private func removeLegacyCertificates() {
        guard let certificatesDirectory else { return }

        let fileManager = FileManager.default

        for fileName in (try? fileManager.contentsOfDirectory(atPath: certificatesDirectory.path)) ?? [] {
            let path = certificatesDirectory.appendingPathComponent(fileName).path
            var isDirectory: ObjCBool = false

            if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue {
                try? fileManager.removeItem(atPath: path)
            }
        }
    }

    private var certificatesDirectory: URL? {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else { return nil }

        let directory = groupURL.appendingPathComponent(Self.certificatesFolder)

        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory
    }
}
