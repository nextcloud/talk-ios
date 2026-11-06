//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

@objc protocol CertificatesTableViewControllerDelegate: AnyObject {
    func certificatesDidChange()
}

class CertificatesTableViewController: UITableViewController {

    weak var delegate: CertificatesTableViewControllerDelegate?

    private struct AcceptedCertificate {
        let host: String
        let subjectSummary: String?
        let acceptedDate: Date?
    }

    private var certificates: [AcceptedCertificate] = []

    private let cellIdentifier = "CertificateCellIdentifier"

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NCAppBranding.styleViewController(self)

        self.navigationItem.title = NSLocalizedString("Certificates", comment: "")

        self.tableView.register(SubtitleTableViewCell.self, forCellReuseIdentifier: cellIdentifier)

        loadCertificates()
    }

    private func loadCertificates() {
        guard let certificateManager = CCCertificate.sharedManager() else { return }

        certificates = certificateManager.acceptedCertificateHosts().map { host in
            let certificateURL: URL? = certificateManager.acceptedCertificateURL(forHost: host)

            return AcceptedCertificate(host: host,
                                       subjectSummary: certificateURL.flatMap { subjectSummary(of: $0) },
                                       acceptedDate: certificateURL.flatMap { creationDate(of: $0) })
        }

        updateEmptyState()
    }

    private func creationDate(of url: URL) -> Date? {
        return try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
    }

    private func subjectSummary(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let certificate = SecCertificateCreateWithData(nil, data as CFData)
        else { return nil }

        return SecCertificateCopySubjectSummary(certificate) as String?
    }

    private func updateEmptyState() {
        guard certificates.isEmpty else {
            tableView.backgroundView = nil
            return
        }

        let emptyLabel = UILabel()
        emptyLabel.text = NSLocalizedString("No accepted certificates", comment: "")
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        tableView.backgroundView = emptyLabel
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return certificates.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard !certificates.isEmpty else { return nil }

        return NSLocalizedString("Certificates you chose to trust for servers whose identity could not be verified. Each certificate is only trusted for the server it was accepted for.", comment: "")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath)
        let certificate = certificates[indexPath.row]

        cell.textLabel?.text = certificate.host
        cell.selectionStyle = .none

        var subtitleComponents: [String] = []

        if let subjectSummary = certificate.subjectSummary, subjectSummary != certificate.host {
            subtitleComponents.append(subjectSummary)
        }

        if let acceptedDate = certificate.acceptedDate {
            let acceptedString = NSLocalizedString("Accepted on %@", comment: "Date when a certificate was accepted, e.g. 'Accepted on Oct 31, 2026'")
            subtitleComponents.append(String(format: acceptedString, NCUtils.readableDate(fromDate: acceptedDate)))
        }

        cell.detailTextLabel?.text = subtitleComponents.isEmpty ? nil : subtitleComponents.joined(separator: " · ")

        return cell
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: nil) { _, _, completionHandler in
            self.removeCertificate(at: indexPath)
            completionHandler(true)
        }
        deleteAction.image = UIImage(systemName: "trash")

        return UISwipeActionsConfiguration(actions: [deleteAction])
    }

    private func removeCertificate(at indexPath: IndexPath) {
        let certificate = certificates[indexPath.row]

        guard CCCertificate.sharedManager()?.removeAcceptedCertificate(forHost: certificate.host) == true else { return }

        certificates.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
        delegate?.certificatesDidChange()

        if certificates.isEmpty {
            // Hides the footer
            tableView.reloadData()
            updateEmptyState()
        }
    }
}
