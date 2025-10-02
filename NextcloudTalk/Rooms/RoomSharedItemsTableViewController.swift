//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import QuickLook

@objcMembers class RoomSharedItemsTableViewController: UITableViewController,
                                                        NCChatFileControllerDelegate,
                                                        QLPreviewControllerDelegate,
                                                        QLPreviewControllerDataSource,
                                                        VLCKitVideoViewControllerDelegate {

    let room: NCRoom
    let itemsOverviewLimit: Int = 1
    let itemLimit: Int = 100
    var sharedItemsOverview: [String: [NCChatMessage]] = [:]
    var currentItems: [NCChatMessage] = []
    var currentItemType: String = "all"
    var currentLastItemId: Int = -1
    var sharedItemsBackgroundView: PlaceholderView = PlaceholderView(for: .insetGrouped)
    var previewControllerFilePath: String = ""
    var isPreviewControllerShown: Bool = false

    weak var previewChatViewController: ContextChatViewController?
    weak var previewNavigationChatViewController: NCNavigationController?

    init(room: NCRoom) {
        self.room = room
        super.init(nibName: "RoomSharedItemsTableViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NCAppBranding.styleViewController(self)

        self.navigationItem.title = NSLocalizedString("Shared items", comment: "")

        self.tableView.separatorInset = UIEdgeInsets(top: 0, left: 64, bottom: 0, right: 0)
        self.tableView.register(UINib(nibName: DirectoryTableViewCell.nibName, bundle: nil), forCellReuseIdentifier: DirectoryTableViewCell.identifier)

        self.hideShowMoreButton()
        self.getItemsOverview()
    }

    func availableItemTypes() -> [String] {
        var availableItemTypes: [String] = []
        for itemType in sharedItemsOverview.keys {
            guard let items = sharedItemsOverview[itemType] else {continue}
            if !items.isEmpty {
                availableItemTypes.append(itemType)
            }
        }
        return availableItemTypes.sorted(by: { $0 < $1 })
    }

    func getItemsForItemType(itemType: String) {
        guard let account = room.account else { return }

        showFetchingItemsPlaceholderView()

        NCAPIController.sharedInstance()
            .getSharedItems(ofType: itemType, fromLastMessageId: currentLastItemId, withLimit: itemLimit,
                            inRoom: room.token, for: account) { items, lastItemId, error, _ in
                if error == nil, let sharedItems = items as? [NCChatMessage] {
                    // Remove deleted files
                    var filteredItems: [NCChatMessage] = []
                    for message in sharedItems {
                        if message.systemMessage == "file_shared" && message.file() == nil {continue}
                        filteredItems.append(message)
                    }
                    // Sort received items
                    let sortedItems = filteredItems.sorted(by: { $0.messageId > $1.messageId })
                    // Set or append items
                    if self.currentLastItemId > 0 {
                        self.currentItems.append(contentsOf: sortedItems)
                    } else {
                        self.currentItems = sortedItems
                    }
                    // Set new last item id
                    self.currentLastItemId = lastItemId
                    // Show ir hide "Show more" button
                    if sharedItems.count == self.itemLimit {
                        self.showShowMoreButton()
                    } else {
                        self.hideShowMoreButton()
                    }
                    // Load items
                    self.tableView.reloadData()
                } else {
                    self.hideShowMoreButton()
                }
                self.hideFetchingItemsPlaceholderView()
            }
    }

    func getItemsOverview() {
        guard let account = room.account else { return }

        showFetchingItemsPlaceholderView()

        NCAPIController.sharedInstance()
            .getSharedItemsOverview(inRoom: room.token, withLimit: itemsOverviewLimit, for: account) { itemsOverview, error, _ in
                if error == nil {
                    self.sharedItemsOverview = itemsOverview as? [String: [NCChatMessage]] ?? [:]
                    let availableItemTypes = self.availableItemTypes()
                    if availableItemTypes.isEmpty {
                        self.hideFetchingItemsPlaceholderView()
                    } else if availableItemTypes.contains(kSharedItemTypeMedia) {
                        self.setupViewForItemType(itemType: kSharedItemTypeMedia)
                    } else if availableItemTypes.contains(kSharedItemTypeFile) {
                        self.setupViewForItemType(itemType: kSharedItemTypeFile)
                    } else if let firstItemType = availableItemTypes.first {
                        self.setupViewForItemType(itemType: firstItemType)
                    }
                } else {
                    self.hideFetchingItemsPlaceholderView()
                }
            }
    }

    func setupViewForItemType(itemType: String) {
        currentItemType = itemType
        currentItems = []
        currentLastItemId = -1
        hideShowMoreButton()
        tableView.reloadData()
        setupTitleButtonForItemType(itemType: itemType)
        getItemsForItemType(itemType: itemType)
    }

    func setupTitleButtonForItemType(itemType: String) {
        let itemTypeSelectorButton = UIButton(type: .custom)
        let buttonTitle = nameForItemType(itemType: itemType) + " ▼"
        itemTypeSelectorButton.setTitle(buttonTitle, for: .normal)
        itemTypeSelectorButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        itemTypeSelectorButton.setTitleColor(NCAppBranding.themeTextColor(), for: .normal)
        self.navigationItem.titleView = itemTypeSelectorButton

        var menuActions: [UIAction] = []

        for itemType in availableItemTypes() {
            let itemTypeName = nameForItemType(itemType: itemType)
            let action = UIAction(title: itemTypeName, image: nil) { [unowned self] _ in
                self.setupViewForItemType(itemType: itemType)
            }

            if itemType == currentItemType {
                action.state = .on
            }

            menuActions.append(action)
        }

        itemTypeSelectorButton.showsMenuAsPrimaryAction = true
        itemTypeSelectorButton.menu = UIMenu(children: menuActions)
    }

    func showFetchingItemsPlaceholderView() {
        sharedItemsBackgroundView.placeholderView.isHidden = true
        sharedItemsBackgroundView.setImage(UIImage(systemName: "photo.on.rectangle.angled"))
        sharedItemsBackgroundView.placeholderImage.contentMode = .scaleAspectFit
        sharedItemsBackgroundView.placeholderTextView.text = NSLocalizedString("No shared items", comment: "")
        sharedItemsBackgroundView.loadingView.startAnimating()
        sharedItemsBackgroundView.loadingView.isHidden = false
        self.tableView.backgroundView = sharedItemsBackgroundView
    }

    func hideFetchingItemsPlaceholderView() {
        sharedItemsBackgroundView.loadingView.stopAnimating()
        sharedItemsBackgroundView.loadingView.isHidden = true
        sharedItemsBackgroundView.placeholderView.isHidden = !currentItems.isEmpty
    }

    func showShowMoreButton() {
        let showMoreButton = UIButton(frame: CGRect(origin: .zero, size: CGSize(width: self.tableView.frame.width, height: 40)))
        showMoreButton.titleLabel?.font = .systemFont(ofSize: 15)
        showMoreButton.setTitleColor(.systemBlue, for: .normal)
        showMoreButton.setTitle(NSLocalizedString("Show more…", comment: ""), for: .normal)
        showMoreButton.addTarget(self, action: #selector(showMoreButtonClicked), for: .touchUpInside)
        self.tableView.tableFooterView = showMoreButton
    }

    func hideShowMoreButton() {
        self.tableView.tableFooterView = UIView()
    }

    func showMoreButtonClicked() {
        let loadingMoreView = UIActivityIndicatorView(frame: CGRect(origin: .zero, size: CGSize(width: 40, height: 40)))
        loadingMoreView.color = .darkGray
        loadingMoreView.startAnimating()
        self.tableView.tableFooterView = loadingMoreView
        getItemsForItemType(itemType: currentItemType)
    }

    func nameForItemType(itemType: String) -> String {
        switch itemType {
        case kSharedItemTypeAudio:
            return NSLocalizedString("Audios", comment: "")
        case kSharedItemTypeDeckcard:
            return NSLocalizedString("Deck cards", comment: "")
        case kSharedItemTypeFile:
            return NSLocalizedString("Files", comment: "")
        case kSharedItemTypeMedia:
            return NSLocalizedString("Media", comment: "")
        case kSharedItemTypeLocation:
            return NSLocalizedString("Locations", comment: "")
        case kSharedItemTypeOther:
            return NSLocalizedString("Others", comment: "")
        case kSharedItemTypeVoice:
            return NSLocalizedString("Voice messages", comment: "")
        case kSharedItemTypePoll:
            return NSLocalizedString("Polls", comment: "")
        case kSharedItemTypeRecording:
            return NSLocalizedString("Recordings", comment: "")
        default:
            return NSLocalizedString("Shared items", comment: "")
        }
    }

    func imageForMessage(message: NCChatMessage) -> UIImage {
        var image = UIImage(named: "file")
        if message.file() != nil {
            let imageName = NCUtils.previewImage(forMimeType: message.file().mimetype)
            image = UIImage(named: imageName)
        }
        if message.geoLocation() != nil {
            image = UIImage(systemName: "mappin")
        }
        if message.deckCard() != nil {
            image = UIImage(named: "deck-item")
        }
        if message.poll != nil {
            image = UIImage(systemName: "chart.bar")
        }
        return image ?? UIImage()
    }

    // MARK: - File downloader

    func downloadFileForCell(cell: DirectoryTableViewCell, file: NCMessageFileParameter) {
        cell.fileParameter = file
        let downloader = NCChatFileController()
        downloader.delegate = self
        downloader.downloadFile(fromMessage: file)
    }

    func fileControllerDidLoadFile(_ fileController: NCChatFileController, with fileStatus: NCChatFileStatus) {
        DispatchQueue.main.async {
            if self.isPreviewControllerShown {
                return
            }

            guard let fileLocalPath = fileStatus.fileLocalPath else { return }

            self.previewControllerFilePath = fileLocalPath
            self.isPreviewControllerShown = true

            let fileExtension = URL(fileURLWithPath: fileLocalPath).pathExtension.lowercased()

            if VLCKitVideoViewController.supportedFileExtensions.contains(fileExtension) {
                let vlcViewController = VLCKitVideoViewController(filePath: fileLocalPath)
                vlcViewController.delegate = self
                vlcViewController.modalPresentationStyle = .fullScreen

                self.present(vlcViewController, animated: true)

                return
            }

            let previewController = QLPreviewController()
            previewController.dataSource = self
            previewController.delegate = self
            self.present(previewController, animated: true)
        }
    }

    func fileControllerDidFailLoadingFile(_ fileController: NCChatFileController, withFileId fileId: String, withErrorDescription errorDescription: String) {
        let alertTitle = NSLocalizedString("Unable to load file", comment: "")
        let alert = UIAlertController(
            title: alertTitle,
            message: errorDescription,
            preferredStyle: .alert)

        let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil)
        alert.addAction(okAction)

        self.present(alert, animated: true, completion: nil)
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return 1
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return NSURL(fileURLWithPath: previewControllerFilePath)
    }

    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        isPreviewControllerShown = false
    }

    func vlckitVideoViewControllerDismissed(_ controller: VLCKitVideoViewController) {
        isPreviewControllerShown = false
    }

    // MARK: - Locations

    func presentLocation(location: GeoLocationRichObject) {
        let mapViewController = MapViewController(geoLocationRichObject: location)
        let navigationViewController = NCNavigationController(rootViewController: mapViewController)
        self.present(navigationViewController, animated: true, completion: nil)
    }

    // MARK: - Polls

    func presentPoll(pollId: Int) {
        let pollViewController = PollVotingView(room: room)
        let navigationViewController = NCNavigationController(rootViewController: pollViewController)
        self.present(navigationViewController, animated: true, completion: nil)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCAPIController.sharedInstance().getPollWithId(pollId, inRoom: room.token, for: activeAccount) { poll, error, _ in
            if let poll = poll, error == nil {
                pollViewController.updatePoll(poll: poll)
            }
        }
    }

    // MARK: - Other files

    func openLink(link: String) {
        NCUtils.openLinkInBrowser(link: link)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return currentItems.count
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return DirectoryTableViewCell.cellHeight
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DirectoryTableViewCell.identifier) as? DirectoryTableViewCell ??
        DirectoryTableViewCell(style: .default, reuseIdentifier: DirectoryTableViewCell.identifier)

        let message = currentItems[indexPath.row]

        if let file = message.file() {
            cell.fileNameLabel?.text = file.name
        } else {
            cell.fileNameLabel?.text = message.parsedMessage().string
        }

        var infoLabelText = NCUtils.relativeTimeFromDate(date: Date(timeIntervalSince1970: Double(message.timestamp)))
        if !message.actorDisplayName.isEmpty {
            infoLabelText += " ⸱ " + message.actorDisplayName
        }
        if let file = message.file(), file.size > 0 {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let sizeString = formatter.string(fromByteCount: Int64(file.size))
            infoLabelText += " ⸱ " + sizeString
        }
        cell.fileInfoLabel?.text = infoLabelText

        let image = imageForMessage(message: message)
        cell.fileImageView?.image = image
        cell.fileImageView?.tintColor = .secondaryLabel
        if message.file()?.previewAvailable != nil {
            cell.fileImageView?.setPreview(forFileId: message.file().parameterId, withWidth: 40, withHeight: 40, usingAccount: .active)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: {

            // Init the BaseChatViewController without message to directly show a preview
            if let account = self.room.account, let chatViewController = ContextChatViewController(forRoom: self.room, withAccount: account, withMessage: [], withHighlightId: 0) {
                self.previewChatViewController = chatViewController

                // Fetch the context of the message and update the BaseChatViewController
                let message = self.currentItems[indexPath.row]
                chatViewController.showContext(ofMessageId: message.messageId, withLimit: 50, withCloseButton: false)

                let navController = NCNavigationController(rootViewController: chatViewController)
                self.previewNavigationChatViewController = navController

                return navController
            }

            return nil
        }, actionProvider: { _ in
            UIMenu(children: [UIAction(title: NSLocalizedString("Open", comment: "")) { _ in
                DispatchQueue.main.async {
                    self.presentPreviewChatViewController()
                }
            }])
        })
    }

    override func tableView(_ tableView: UITableView, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
        animator.addAnimations {
            self.presentPreviewChatViewController()
        }
    }

    func presentPreviewChatViewController() {
        guard let previewNavigationChatViewController = self.previewNavigationChatViewController,
              let previewChatViewController = self.previewChatViewController
        else { return }

        self.present(previewNavigationChatViewController, animated: false)

        previewChatViewController.navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Close", comment: ""), primaryAction: UIAction { [weak previewChatViewController] _ in
            previewChatViewController?.dismiss(animated: true)
        })
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let cell = tableView.cellForRow(at: indexPath) as? DirectoryTableViewCell ?? DirectoryTableViewCell()
        let message = currentItems[indexPath.row]

        self.tableView.deselectRow(at: indexPath, animated: true)

        switch currentItemType {
        case kSharedItemTypeMedia, kSharedItemTypeFile, kSharedItemTypeVoice, kSharedItemTypeAudio, kSharedItemTypeRecording:
            if let file = message.file() {
                downloadFileForCell(cell: cell, file: file)
            }
        case kSharedItemTypeLocation:
            if let geoLocation = message.geoLocation() {
                presentLocation(location: GeoLocationRichObject(from: geoLocation))
            }
        case kSharedItemTypeDeckcard, kSharedItemTypeOther:
            if let link = message.objectShareLink() {
                openLink(link: link)
            }
        case kSharedItemTypePoll:
            if let poll = message.poll, let pollId = Int(poll.parameterId) {
                presentPoll(pollId: pollId)
            }
        default:
            return
        }
    }
}
