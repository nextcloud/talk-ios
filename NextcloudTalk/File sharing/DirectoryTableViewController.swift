//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import NextcloudKit

class DirectoryTableViewController: UITableViewController {

    private let path: String
    private let token: String
    private let threadId: Int

    private var userHomePath = ""
    private var itemsInDirectory: [NKFile] = []
    private var sortingButton: UIBarButtonItem?
    private let directoryBackgroundView = PlaceholderView()
    private let sharingFileView = UIActivityIndicatorView()

    init(path: String, inRoom token: String, andThread threadId: Int) {
        self.path = path
        self.token = token
        self.threadId = threadId

        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        userHomePath = NCAPIController.sharedInstance().filesPath(forAccount: activeAccount)

        configureNavigationBar()

        if #available(iOS 26.0, *) {
            sharingFileView.color = .label
        } else {
            sharingFileView.color = NCAppBranding.themeTextColor()
        }

        self.tableView.tableFooterView = UIView(frame: .zero)

        // Directory placeholder view
        directoryBackgroundView.setImage(UIImage(named: "folder-placeholder"))
        directoryBackgroundView.placeholderTextView.text = NSLocalizedString("No files in here", comment: "")
        directoryBackgroundView.placeholderView.isHidden = true
        directoryBackgroundView.loadingView.startAnimating()
        self.tableView.backgroundView = directoryBackgroundView

        NCAppBranding.styleViewController(self)

        self.tableView.separatorInset = UIEdgeInsets(top: 0, left: 64, bottom: 0, right: 0)

        self.tableView.register(UINib(nibName: DirectoryTableViewCell.nibName, bundle: nil), forCellReuseIdentifier: DirectoryTableViewCell.identifier)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        getItemsInDirectory()
    }

    @objc private func cancelButtonPressed() {
        self.dismiss(animated: true)
    }

    @objc private func shareButtonPressed() {
        showConfirmationDialogForSharingItem(withPath: path, andName: (path as NSString).lastPathComponent)
    }

    private func addMenuToSortingButton() {
        let preferredSorting = NCSettingsController.sharedInstance().getPreferredFileSorting()

        let alphabeticalAction = UIAction(title: NSLocalizedString("Alphabetical order", comment: ""), image: UIImage(systemName: "character.square")) { [weak self] _ in
            NCSettingsController.sharedInstance().setPreferredFileSorting(.alphabeticalSorting)
            self?.sortItemsInDirectory()
        }

        alphabeticalAction.state = preferredSorting == .alphabeticalSorting ? .on : .off

        let modificationDateAction = UIAction(title: NSLocalizedString("Modification date", comment: ""), image: UIImage(systemName: "clock")) { [weak self] _ in
            NCSettingsController.sharedInstance().setPreferredFileSorting(.modificationDateSorting)
            self?.sortItemsInDirectory()
        }

        modificationDateAction.state = preferredSorting == .modificationDateSorting ? .on : .off

        sortingButton?.menu = UIMenu(children: [alphabeticalAction, modificationDateAction])
    }

    // MARK: - Files

    private func getItemsInDirectory() {
        NCAPIController.sharedInstance().readFolder(forAccount: NCDatabaseManager.sharedInstance().activeAccount(), atPath: path, withDepth: "1") { [weak self] items, error in
            guard let self, let items, error == nil else { return }

            let currentDirectory = self.path.isEmpty ? "/" : (self.path as NSString).lastPathComponent
            var itemsInDirectory: [NKFile] = []

            for item in items {
                var itemPath = item.path.replacingOccurrences(of: self.userHomePath, with: "")

                // When nextcloud is installed in a subdirectory, it's not enough to replace the userHomePath,
                // because the subdirectory would get a part of the itemPath (see https://github.com/nextcloud/talk-ios/issues/996)
                let itemPathParts = item.path.components(separatedBy: self.userHomePath)
                if itemPathParts.count > 1 {
                    itemPath = itemPathParts[1]
                }

                if (itemPath as NSString).lastPathComponent == currentDirectory, !item.e2eEncrypted {
                    itemsInDirectory.append(item)
                }
            }

            self.itemsInDirectory = itemsInDirectory
            self.sortItemsInDirectory()

            self.directoryBackgroundView.loadingView.stopAnimating()
            self.directoryBackgroundView.loadingView.isHidden = true
            self.directoryBackgroundView.placeholderView.isHidden = !itemsInDirectory.isEmpty
        }
    }

    private func sortItemsInDirectory() {
        if NCSettingsController.sharedInstance().getPreferredFileSorting() == .alphabeticalSorting {
            itemsInDirectory.sort { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }
        } else {
            itemsInDirectory.sort { ($0.date as Date) > ($1.date as Date) }
        }

        addMenuToSortingButton()
        self.tableView.reloadData()
    }

    private func shareFile(withPath path: String) {
        setSharingFileUI()

        var talkMetaData: [String: Any] = [:]
        if threadId > 0 {
            talkMetaData["threadId"] = threadId
        }

        NCAPIController.sharedInstance().shareFileOrFolder(forAccount: NCDatabaseManager.sharedInstance().activeAccount(), atPath: path, toRoom: token, withTalkMetaData: talkMetaData, withReferenceId: nil) { [weak self] error in
            guard let self else { return }

            if let error {
                self.removeSharingFileUI()
                self.showErrorSharingItem()
                print("Error sharing file or folder: \(error)")
            } else {
                self.dismiss(animated: true)
            }
        }
    }

    // MARK: - Utils

    private func configureNavigationBar() {
        // Sorting button
        let sortingButton = UIBarButtonItem(image: UIImage(systemName: "arrow.up.arrow.down"), style: .plain, target: self, action: nil)
        self.sortingButton = sortingButton
        addMenuToSortingButton()

        // Home folder
        if path.isEmpty {
            self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelButtonPressed))
            self.navigationItem.rightBarButtonItem = sortingButton

            let navigationLogo = UIImage(systemName: "house")
            let navigationImageView = UIImageView(image: navigationLogo)
            navigationImageView.image = navigationImageView.image?.withRenderingMode(.alwaysTemplate)
            if #available(iOS 26.0, *) {
                navigationImageView.tintColor = .label
            } else {
                navigationImageView.tintColor = NCAppBranding.themeTextColor()
            }
            self.navigationItem.titleView = navigationImageView

            self.navigationItem.backBarButtonItem = UIBarButtonItem(image: navigationLogo, style: .plain, target: nil, action: nil)
            // Other directories
        } else {
            let shareButton = UIBarButtonItem(image: UIImage(named: "sharing"), style: .plain, target: self, action: #selector(shareButtonPressed))
            self.navigationItem.rightBarButtonItems = [sortingButton, shareButton]

            self.navigationItem.title = (path as NSString).lastPathComponent
        }
    }

    private func setSharingFileUI() {
        sharingFileView.startAnimating()
        self.navigationItem.rightBarButtonItems = [UIBarButtonItem(customView: sharingFileView)]
        self.navigationController?.navigationBar.isUserInteractionEnabled = false
        self.tableView.isUserInteractionEnabled = false
    }

    private func removeSharingFileUI() {
        sharingFileView.stopAnimating()
        configureNavigationBar()
        self.navigationController?.navigationBar.isUserInteractionEnabled = true
        self.tableView.isUserInteractionEnabled = true
    }

    private func showConfirmationDialogForSharingItem(withPath path: String, andName name: String) {
        let confirmDialog = UIAlertController(title: name,
                                              message: String(format: NSLocalizedString("Do you want to share '%@' in the conversation?", comment: ""), name),
                                              preferredStyle: .alert)
        confirmDialog.addAction(UIAlertAction(title: NSLocalizedString("Share", comment: ""), style: .default) { [weak self] _ in
            self?.shareFile(withPath: path)
        })
        confirmDialog.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        self.present(confirmDialog, animated: true)
    }

    private func showErrorSharingItem() {
        let confirmDialog = UIAlertController(title: NSLocalizedString("Could not share file", comment: ""),
                                              message: NSLocalizedString("An error occurred while sharing the file", comment: ""),
                                              preferredStyle: .alert)
        confirmDialog.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        self.present(confirmDialog, animated: true)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return itemsInDirectory.count
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return DirectoryTableViewCell.cellHeight
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = itemsInDirectory[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: DirectoryTableViewCell.identifier) as? DirectoryTableViewCell ??
                   DirectoryTableViewCell(style: .default, reuseIdentifier: DirectoryTableViewCell.identifier)

        // Name and modification date
        cell.fileNameLabel.text = item.fileName
        cell.fileInfoLabel.text = NCUtils.relativeTimeFromDate(date: item.date as Date)

        // Icon or preview
        if item.directory {
            cell.fileImageView.image = UIImage(named: "folder")
        } else if item.hasPreview {
            cell.fileImageView.setPreview(forFileId: item.fileId, withWidth: 40, withHeight: 40, usingAccount: NCDatabaseManager.sharedInstance().activeAccount())
        } else {
            cell.fileImageView.image = UIImage(named: NCUtils.previewImage(forMimeType: item.contentType))
        }

        // Disclosure indicator
        cell.accessoryType = item.directory ? .disclosureIndicator : .none

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = itemsInDirectory[indexPath.row]
        let selectedItemPath = "\(path)/\(item.fileName)"

        if item.directory {
            let directoryVC = DirectoryTableViewController(path: selectedItemPath, inRoom: token, andThread: threadId)
            self.navigationController?.pushViewController(directoryVC, animated: true)
        } else {
            showConfirmationDialogForSharingItem(withPath: selectedItemPath, andName: item.fileName)
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }
}
