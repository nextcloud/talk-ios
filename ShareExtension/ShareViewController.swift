//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import Intents
import UniformTypeIdentifiers

protocol ShareViewControllerDelegate: AnyObject {
    func shareViewControllerDidCancel(_ viewController: ShareViewController)
}

// Share.storyboard references the class without a module
@objc(ShareViewController)
class ShareViewController: UITableViewController, UISearchControllerDelegate, UISearchResultsUpdating, ShareConfirmationViewControllerDelegate {

    weak var delegate: ShareViewControllerDelegate?

    private weak var chatViewController: UIViewController?
    private var forwardMessage: String?
    private var forwardObjectShareMessage: NCChatMessage?
    private var forwarding = false

    private var searchController: UISearchController!
    private var resultTableViewController: UITableViewController!
    private var rooms: [NCRoom] = []
    private var filteredRooms: [NCRoom] = []
    private var roomsBackgroundView: PlaceholderView!
    private var roomSearchBackgroundView: PlaceholderView!
    private var shareAccount: TalkAccount?
    private var serverCapabilities: ServerCapabilities?
    private var realm: RLMRealm?

    init(toForwardMessage message: String, fromChatViewController chatViewController: UIViewController) {
        self.chatViewController = chatViewController
        self.forwardMessage = message
        self.forwarding = true

        super.init(style: .plain)
    }

    init(toForwardObjectShare objectShareMessage: NCChatMessage, fromChatViewController chatViewController: UIViewController) {
        self.chatViewController = chatViewController
        self.forwardObjectShareMessage = objectShareMessage
        self.forwarding = true

        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let realm = openDatabase() else {
            self.cancelExtensionRequest()
            return
        }

        self.realm = realm

        if let intent = self.extensionContext?.intent as? INSendMessageIntent,
           let conversationIdentifier = intent.conversationIdentifier,
           let managedRoom = NCRoom.objects(in: realm, with: NSPredicate(format: "internalId = %@", conversationIdentifier)).firstObject() as? NCRoom {

            let room = NCRoom(value: managedRoom)

            if room.isFederated {
                self.showFederatedAlert()
                self.cancelExtensionRequest()
                return
            }

            if let managedAccount = TalkAccount.objects(in: realm, with: NSPredicate(format: "accountId = %@", room.accountId)).firstObject() as? TalkAccount {
                let intentAccount = TalkAccount(value: managedAccount)
                self.setupShareView(forAccount: intentAccount)

                if let serverCapabilities,
                   let shareConfirmationVC = ShareConfirmationViewController(room: room, thread: nil, account: intentAccount, serverCapabilities: serverCapabilities) {

                    shareConfirmationVC.delegate = self
                    shareConfirmationVC.isModal = true
                    self.setSharedItems(to: shareConfirmationVC)
                    self.navigationController?.pushViewController(shareConfirmationVC, animated: true)

                    return
                }
            }
        }

        self.setupShareView(forAccount: nil)

        let bundle = Bundle(for: ShareTableViewCell.self)
        let cellNib = UINib(nibName: ShareTableViewCell.nibName, bundle: bundle)

        self.tableView.register(cellNib, forCellReuseIdentifier: ShareTableViewCell.identifier)
        self.tableView.separatorInset = UIEdgeInsets(top: 0, left: 60, bottom: 0, right: 0)
        self.tableView.tableFooterView = UIView(frame: .zero)

        resultTableViewController = UITableViewController()
        resultTableViewController.tableView.delegate = self
        resultTableViewController.tableView.dataSource = self
        resultTableViewController.tableView.register(cellNib, forCellReuseIdentifier: ShareTableViewCell.identifier)
        resultTableViewController.tableView.separatorInset = UIEdgeInsets(top: 0, left: 60, bottom: 0, right: 0)
        resultTableViewController.tableView.tableFooterView = UIView(frame: .zero)

        searchController = UISearchController(searchResultsController: resultTableViewController)
        searchController.delegate = self
        searchController.searchResultsUpdater = self
        searchController.searchBar.sizeToFit()

        self.navigationItem.searchController = searchController
        self.navigationItem.hidesSearchBarWhenScrolling = false

        NCAppBranding.styleViewController(self)

        self.navigationItem.title = forwarding ? NSLocalizedString("Forward to", comment: "") : NSLocalizedString("Share with", comment: "")

        let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelButtonPressed))
        cancelButton.accessibilityHint = NSLocalizedString("Double tap to dismiss sharing options", comment: "")
        self.navigationController?.navigationBar.topItem?.leftBarButtonItem = cancelButton

        // Place resultTableViewController correctly
        self.definesPresentationContext = true

        roomsBackgroundView = PlaceholderView()
        roomsBackgroundView.setImage(UIImage(named: "conversations-placeholder"))
        roomsBackgroundView.placeholderTextView.text = NSLocalizedString("You are not part of any conversation", comment: "")
        roomsBackgroundView.placeholderView.isHidden = !rooms.isEmpty
        roomsBackgroundView.loadingView.isHidden = true
        self.tableView.backgroundView = roomsBackgroundView

        roomSearchBackgroundView = PlaceholderView()
        roomSearchBackgroundView.setImage(UIImage(named: "conversations-placeholder"))
        roomSearchBackgroundView.placeholderTextView.text = NSLocalizedString("No results found", comment: "")
        roomSearchBackgroundView.placeholderView.isHidden = true
        roomSearchBackgroundView.loadingView.isHidden = true
        resultTableViewController.tableView.backgroundView = roomSearchBackgroundView

        // Fix uisearchcontroller animation
        self.extendedLayoutIncludesOpaqueBars = true
    }

    // MARK: - Database

    private func openDatabase() -> RLMRealm? {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else { return nil }

        let databaseURL = groupURL.appendingPathComponent(kTalkDatabaseFolder).appendingPathComponent(kTalkDatabaseFileName)

        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            NSLog("Database does not exist -> main app needs to run before extension.")
            return nil
        }

        do {
            let currentSchemaVersion = try RLMRealm.schemaVersion(at: databaseURL)
            NSLog("Current schemaVersion is %llu app schemaVersion is %llu", currentSchemaVersion, kTalkDatabaseSchemaVersion)

            if currentSchemaVersion != kTalkDatabaseSchemaVersion {
                NSLog("Database needs migration -> don't open database from extension")
                return nil
            }
        } catch {
            NSLog("Reading schemaVersion failed: %@", error.localizedDescription)
            return nil
        }

        let configuration = RLMRealmConfiguration.default()
        configuration.fileURL = databaseURL
        configuration.schemaVersion = kTalkDatabaseSchemaVersion
        configuration.objectClasses = [TalkAccount.self, NCRoom.self, ServerCapabilities.self, FederatedCapabilities.self]
        // An empty block is still needed to mark the schema as upgraded (automatically) by Realm
        configuration.migrationBlock = { _, _ in }

        // When forwarding from the app, the app's default configuration must stay untouched
        if Bundle.main.bundlePath.hasSuffix(".appex") {
            RLMRealmConfiguration.setDefault(configuration)
        }

        return try? RLMRealm(configuration: configuration)
    }

    private func cancelExtensionRequest() {
        self.extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: 0))
    }

    // MARK: - Navigation buttons

    @objc private func cancelButtonPressed() {
        self.delegate?.shareViewControllerDidCancel(self)
        self.cancelExtensionRequest()
    }

    // MARK: - Accounts

    private func setProfileButton(forAccount account: TalkAccount) {
        let profileButton = UIButton(type: .custom)
        profileButton.addTarget(self, action: #selector(showAccountSelector), for: .touchUpInside)
        profileButton.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        profileButton.accessibilityLabel = NSLocalizedString("User profile and settings", comment: "")
        profileButton.accessibilityHint = NSLocalizedString("Double tap to go to user profile and application settings", comment: "")

        if let profileImage = NCAPIController.sharedInstance().userProfileImage(forAccount: account, withStyle: self.traitCollection.userInterfaceStyle) {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3.0
            let bounds = profileButton.bounds

            let roundedImage = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
                UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height).addClip()
                profileImage.draw(in: bounds)
            }

            profileButton.setImage(roundedImage, for: .normal)
        } else {
            profileButton.setImage(UIImage(systemName: "person"), for: .normal)
            profileButton.contentMode = .center
        }

        let profileBarButtonItem = UIBarButtonItem(customView: profileButton)
        profileButton.widthAnchor.constraint(equalToConstant: 30).isActive = true
        profileButton.heightAnchor.constraint(equalToConstant: 30).isActive = true

        self.navigationItem.rightBarButtonItem = profileBarButtonItem
    }

    private func setupShareView(forAccount account: TalkAccount?) {
        guard let realm else { return }

        if let account {
            shareAccount = account
        } else if let managedActiveAccount = TalkAccount.objects(in: realm, with: NSPredicate(format: "active = true")).firstObject() as? TalkAccount {
            shareAccount = TalkAccount(value: managedActiveAccount)
        } else {
            // No account is configured in the app yet
            shareAccount = nil
            return
        }

        guard let shareAccount else { return }

        if TalkAccount.allObjects(in: realm).count > 1 {
            self.setProfileButton(forAccount: shareAccount)
        }

        rooms = NCDatabaseManager.sharedInstance().roomsForAccountId(shareAccount.accountId, withRealm: realm)

        if let managedServerCapabilities = ServerCapabilities.objects(in: realm, with: NSPredicate(format: "accountId = %@", shareAccount.accountId)).firstObject() as? ServerCapabilities {
            serverCapabilities = ServerCapabilities(value: managedServerCapabilities)
        } else {
            serverCapabilities = nil
        }

        self.tableView.reloadData()
    }

    @objc private func showAccountSelector() {
        guard let realm else { return }

        let optionsActionSheet = UIAlertController(title: NSLocalizedString("Accounts", comment: ""), message: nil, preferredStyle: .actionSheet)

        for case let managedAccount as TalkAccount in TalkAccount.allObjects(in: realm) {
            let account = TalkAccount(value: managedAccount)

            let action = UIAlertAction(title: account.userDisplayName, style: .default) { _ in
                self.setupShareView(forAccount: account)
            }

            if shareAccount?.accountId == account.accountId {
                action.setValue(UIImage(named: "checkmark")?.withRenderingMode(.alwaysOriginal), forKey: "image")
            }

            optionsActionSheet.addAction(action)
        }

        optionsActionSheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))

        // Presentation on iPads
        optionsActionSheet.popoverPresentationController?.barButtonItem = self.navigationItem.rightBarButtonItem

        self.present(optionsActionSheet, animated: true)
    }

    // MARK: - Shared items

    // swiftlint:disable:next cyclomatic_complexity
    private func setSharedItems(to shareConfirmationVC: ShareConfirmationViewController) {
        let inputItems = self.extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let shareItemController = shareConfirmationVC.shareItemController

        NSLog("Received %lu files to share", inputItems.count)

        for itemProvider in inputItems.flatMap({ $0.attachments ?? [] }) {
            if itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                itemProvider.loadItem(forTypeIdentifier: UTType.movie.identifier) { item, _ in
                    guard let videoURL = item as? URL else { return }

                    NSLog("Shared Video = %@", videoURL.absoluteString)
                    shareItemController.addItem(with: videoURL)
                }

                continue
            }

            // Make sure this is checked before image! Otherwise sharing images from Mail won't work >= iOS 13
            if itemProvider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                itemProvider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    guard let fileURL = item as? URL else { return }

                    NSLog("Shared File URL = %@", fileURL.absoluteString)
                    shareItemController.addItem(with: fileURL)
                }

                continue
            }

            if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                itemProvider.loadItem(forTypeIdentifier: UTType.image.identifier) { item, _ in
                    if let imageURL = item as? URL {
                        NSLog("Shared Image = %@", imageURL.absoluteString)
                        shareItemController.addItem(with: imageURL)
                    } else if let image = item as? UIImage {
                        // Occurs when sharing a screenshot
                        NSLog("Shared UIImage = %@", image)
                        shareItemController.addItem(with: image)
                    } else if let imageData = item as? Data, let image = UIImage(data: imageData) {
                        // Screenshots starting iOS 26
                        NSLog("Shared UIImage = %@", image)
                        shareItemController.addItem(with: image)
                    }
                }

                continue
            }

            // Apple Wallet
            if itemProvider.hasItemConformingToTypeIdentifier("com.apple.pkpass") {
                itemProvider.loadItem(forTypeIdentifier: "com.apple.pkpass") { item, _ in
                    guard let passData = item as? Data else { return }

                    NSLog("Shared Pass")
                    let passFileName = String(format: "Pass_%.f.pkpass", Date().timeIntervalSince1970 * 1000)
                    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(passFileName)

                    try? passData.write(to: tempURL, options: .atomic)
                    shareItemController.addItem(withURLAndName: tempURL, withName: passFileName)
                }

                continue
            }

            // URL, text and vCard are not exclusive, as one item may provide several of them
            if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                    guard let sharedURL = item as? URL, !sharedURL.absoluteString.isEmpty else { return }

                    NSLog("Shared URL = %@", sharedURL.absoluteString)
                    DispatchQueue.main.async {
                        shareConfirmationVC.shareText(sharedURL.absoluteString)
                    }
                }
            }

            if itemProvider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                itemProvider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                    guard let sharedText = item as? String, !sharedText.isEmpty else { return }

                    NSLog("Shared Text = %@", sharedText)
                    DispatchQueue.main.async {
                        shareConfirmationVC.shareText(sharedText)
                    }
                }
            }

            if itemProvider.hasItemConformingToTypeIdentifier(UTType.vCard.identifier) {
                itemProvider.loadItem(forTypeIdentifier: UTType.vCard.identifier) { item, _ in
                    guard let contactData = item as? Data else { return }

                    NSLog("Shared Contact")
                    shareItemController.addItem(withContactData: contactData)
                }
            }
        }
    }

    // MARK: - Search controller

    func updateSearchResults(for searchController: UISearchController) {
        let searchString = searchController.searchBar.text ?? ""

        filteredRooms = rooms.filter { ($0.displayName ?? "").range(of: searchString, options: .caseInsensitive) != nil }
        roomSearchBackgroundView.placeholderView.isHidden = !filteredRooms.isEmpty
        resultTableViewController.tableView.reloadData()
    }

    // MARK: - ShareConfirmationViewController Delegate

    func shareConfirmationViewControllerDidFail(_ viewController: ShareConfirmationViewController) {
        self.extensionContext?.completeRequest(returningItems: [])
    }

    func shareConfirmationViewControllerDidFinish(_ viewController: ShareConfirmationViewController) {
        self.extensionContext?.completeRequest(returningItems: [])
    }

    func shareConfirmationViewControllerDidCancel(_ viewController: ShareConfirmationViewController) {
        self.extensionContext?.completeRequest(returningItems: [])
    }

    // MARK: - Table view data source

    private func rooms(for tableView: UITableView) -> [NCRoom] {
        return tableView == resultTableViewController?.tableView ? filteredRooms : rooms
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return rooms(for: tableView).count
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return ShareTableViewCell.cellHeight
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let room = rooms(for: tableView)[indexPath.row]

        guard let cell = tableView.dequeueReusableCell(withIdentifier: ShareTableViewCell.identifier) as? ShareTableViewCell else {
            return UITableViewCell()
        }

        cell.titleLabel.text = room.displayName
        cell.avatarImageView.setAvatar(for: room)
        cell.accessoryType = .disclosureIndicator

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.tableView.deselectRow(at: indexPath, animated: true)

        let room = rooms(for: tableView)[indexPath.row]

        if room.isFederated {
            self.showFederatedAlert()
            return
        }

        if !room.canChat || room.readOnlyState == .readOnly {
            self.showChatPermissionAlert()
            return
        }

        guard let shareAccount, let serverCapabilities,
              let shareConfirmationVC = ShareConfirmationViewController(room: room, thread: nil, account: shareAccount, serverCapabilities: serverCapabilities)
        else { return }

        shareConfirmationVC.delegate = self

        if let forwardMessage {
            shareConfirmationVC.delegate = chatViewController as? ShareConfirmationViewControllerDelegate
            shareConfirmationVC.forwardingMessage = true
            shareConfirmationVC.shareText(forwardMessage)
        } else if let forwardObjectShareMessage {
            shareConfirmationVC.delegate = chatViewController as? ShareConfirmationViewControllerDelegate
            shareConfirmationVC.forwardingMessage = true
            shareConfirmationVC.shareObjectShareMessage(forwardObjectShareMessage)
        } else {
            self.setSharedItems(to: shareConfirmationVC)
        }

        self.navigationController?.pushViewController(shareConfirmationVC, animated: true)
    }

    // MARK: - Alerts

    private func showChatPermissionAlert() {
        self.showAlert(title: NSLocalizedString("Cannot share to conversation", comment: ""),
                       message: NSLocalizedString("Either you don't have chat permission or the conversation is read-only.", comment: ""))
    }

    private func showFederatedAlert() {
        self.showAlert(title: NSLocalizedString("Cannot share to conversation", comment: ""),
                       message: NSLocalizedString("Sharing to a federated conversation is not supported.", comment: ""))
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))

        self.present(alert, animated: true)
    }
}
