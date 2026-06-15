//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import QuickLook

class LogfilesTableViewController: UITableViewController, QLPreviewControllerDataSource {

    private var logfiles: [URL] = []
    private var selectedLogfile: URL?

    private let cellIdentifier = "LogfileCellIdentifier"

    private lazy var selectBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Select", comment: ""), style: .plain, target: self, action: #selector(selectButtonPressed))
    private lazy var exportBarButtonItem = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(exportButtonPressed))

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NCAppBranding.styleViewController(self)

        self.navigationItem.title = NSLocalizedString("Logs", comment: "")

        self.tableView.register(SubtitleTableViewCell.self, forCellReuseIdentifier: cellIdentifier)
        self.tableView.allowsMultipleSelectionDuringEditing = true

        self.logfiles = NCLog.getLogfiles()

        if !logfiles.isEmpty {
            self.navigationItem.rightBarButtonItem = selectBarButtonItem
        }
    }

    // MARK: - Editing / selection

    @objc func selectButtonPressed() {
        setEditing(!isEditing, animated: true)
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)

        if editing {
            selectBarButtonItem.title = NSLocalizedString("Cancel", comment: "")
        } else {
            selectBarButtonItem.title = NSLocalizedString("Select", comment: "")
        }

        updateExportButton()
    }

    private func updateExportButton() {
        let selectedCount = tableView.indexPathsForSelectedRows?.count ?? 0

        // Offer the export action next to the cancel button once at least one logfile is selected
        if isEditing, selectedCount > 0 {
            self.navigationItem.rightBarButtonItems = [selectBarButtonItem, exportBarButtonItem]
        } else {
            self.navigationItem.rightBarButtonItems = [selectBarButtonItem]
        }
    }

    @objc func exportButtonPressed() {
        guard let selectedIndexPaths = tableView.indexPathsForSelectedRows, !selectedIndexPaths.isEmpty else { return }

        let selectedFiles = selectedIndexPaths.map { logfiles[$0.row] }

        let activityViewController = UIActivityViewController(activityItems: selectedFiles, applicationActivities: nil)
        activityViewController.popoverPresentationController?.barButtonItem = exportBarButtonItem
        activityViewController.completionWithItemsHandler = { [weak self] _, completed, _, _ in
            if completed {
                self?.setEditing(false, animated: true)
            }
        }

        self.present(activityViewController, animated: true)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return logfiles.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath)
        let logfile = logfiles[indexPath.row]

        cell.textLabel?.text = logfile.lastPathComponent

        var subtitleComponents: [String] = []

        if let fileAttributes = try? FileManager.default.attributesOfItem(atPath: logfile.path) {
            if let modificationDate = fileAttributes[.modificationDate] as? Date {
                subtitleComponents.append(NCUtils.readableDate(fromDate: modificationDate))
            }

            if let fileSize = fileAttributes[.size] as? Int64 {
                subtitleComponents.append(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
            }
        }

        cell.detailTextLabel?.text = subtitleComponents.isEmpty ? nil : subtitleComponents.joined(separator: " · ")

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if isEditing {
            updateExportButton()
            return
        }

        self.tableView.deselectRow(at: indexPath, animated: true)

        selectedLogfile = logfiles[indexPath.row]

        // QLPreviewController shows a built-in share button to export a single logfile
        let previewController = QLPreviewController()
        previewController.dataSource = self
        self.present(previewController, animated: true)
    }

    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if isEditing {
            updateExportButton()
        }
    }

    // MARK: - QLPreviewControllerDataSource

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return selectedLogfile != nil ? 1 : 0
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return (selectedLogfile ?? URL(fileURLWithPath: "")) as NSURL
    }
}
