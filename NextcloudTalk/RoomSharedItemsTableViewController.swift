//
// Copyright (c) 2022 Ivan Sein <ivan@nextcloud.com>
//
// Author Ivan Sein <ivan@nextcloud.com>
//
// GNU GPL version 3 or any later version
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import UIKit
import QuickLook

@objcMembers class RoomSharedItemsTableViewController: UITableViewController,
                                                        NCChatFileControllerDelegate,
                                                        QLPreviewControllerDelegate,
                                                        QLPreviewControllerDataSource,
                                                        VLCKitVideoViewControllerDelegate {

    let room: NCRoom
    let account: TalkAccount = NCDatabaseManager.sharedInstance().activeAccount()
    let itemsOverviewLimit: Int = 1
    let itemLimit: Int = 100
    var sharedItemsOverview: [String: [NCChatMessage]] = [:]
    var currentItems: [NCChatMessage] = []
    var currentItemType: String = "all"
    var currentLastItemId: Int = -1
    var sharedItemsBackgroundView: PlaceholderView = PlaceholderView()
    var previewControllerFilePath: String = ""
    var isPreviewControllerShown: Bool = false

    init(room: NCRoom) {
        self.room = room
        super.init(nibName: "RoomSharedItemsTableViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: NCAppBranding.themeTextColor()]
        self.navigationController?.navigationBar.tintColor = NCAppBranding.themeTextColor()
        self.navigationController?.navigationBar.barTintColor = NCAppBranding.themeColor()
        self.navigationController?.navigationBar.isTranslucent = false
        self.navigationItem.title = NSLocalizedString("Shared items", comment: "")

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.titleTextAttributes = [.foregroundColor: NCAppBranding.themeTextColor()]
        appearance.backgroundColor = NCAppBranding.themeColor()
        self.navigationItem.standardAppearance = appearance
        self.navigationItem.compactAppearance = appearance
        self.navigationItem.scrollEdgeAppearance = appearance

        self.tableView.separatorInset = UIEdgeInsets(top: 0, left: 64, bottom: 0, right: 0)
        self.tableView.register(UINib(nibName: kDirectoryTableCellNibName, bundle: nil), forCellReuseIdentifier: kDirectoryCellIdentifier)

        self.hideShowMoreButton()
        self.getItemsOverview()
    }

    func presentItemTypeSelector() {
        let itemTypesActionSheet = UIAlertController(title: NSLocalizedString("Shared items", comment: ""), message: nil, preferredStyle: .actionSheet)

        for itemType in availableItemTypes() {
            let itemTypeName = nameForItemType(itemType: itemType)
            let action = UIAlertAction(title: itemTypeName, style: .default) { _ in
                self.setupViewForItemType(itemType: itemType)
            }

            if itemType == currentItemType {
                action.setValue(UIImage(named: "checkmark")?.withRenderingMode(_: .alwaysOriginal), forKey: "image")
            }
            itemTypesActionSheet.addAction(action)
        }

        itemTypesActionSheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))

        // Presentation on iPads
        itemTypesActionSheet.popoverPresentationController?.sourceView = self.navigationItem.titleView
        itemTypesActionSheet.popoverPresentationController?.sourceRect = self.navigationItem.titleView?.frame ?? CGRect()

        self.present(itemTypesActionSheet, animated: true, completion: nil)
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
        itemTypeSelectorButton.addTarget(self, action: #selector(presentItemTypeSelector), for: .touchUpInside)
        self.navigationItem.titleView = itemTypeSelectorButton
    }

    func showFetchingItemsPlaceholderView() {
        sharedItemsBackgroundView.placeholderView.isHidden = true
        sharedItemsBackgroundView.setImage(UIImage(named: "media-placeholder"))
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

    func imageNameForMessage(message: NCChatMessage) -> String {
        var imageName = "file"
        if message.file() != nil {
            imageName = NCUtils.previewImage(forFileMIMEType: message.file().mimetype)
        }
        if message.geoLocation() != nil {
            imageName = "location-item"
        }
        if message.deckCard() != nil {
            imageName = "deck-item"
        }
        if message.poll() != nil {
            imageName = "poll-item"
        }
        return imageName
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

            self.previewControllerFilePath = fileStatus.fileLocalPath
            self.isPreviewControllerShown = true

            let fileExtension = NSURL(fileURLWithPath: fileStatus.fileLocalPath).pathExtension

            if fileExtension?.lowercased() == "webm" {
                let vlcViewController = VLCKitVideoViewController(filePath: fileStatus.fileLocalPath)
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

    func fileControllerDidFailLoadingFile(_ fileController: NCChatFileController, withErrorDescription errorDescription: String) {
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
        let pollViewController = PollVotingView(style: .insetGrouped)
        pollViewController.room = room
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
        NCUtils.openLink(inBrowser: link)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return currentItems.count
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return kDirectoryTableCellHeight
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: kDirectoryCellIdentifier) as? DirectoryTableViewCell ??
        DirectoryTableViewCell(style: .default, reuseIdentifier: kShareCellIdentifier)

        let message = currentItems[indexPath.row]

        cell.fileNameLabel?.text = message.parsedMessage().string
        var infoLabelText = NCUtils.relativeTime(from: Date(timeIntervalSince1970: Double(message.timestamp)))
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

        let image = UIImage(named: imageNameForMessage(message: message))
        cell.fileImageView?.image = image
        if message.file()?.previewAvailable != nil {
            cell.fileImageView?
                .setImageWith(NCAPIController.sharedInstance().createPreviewRequest(forFile: message.file().parameterId,
                                                                                    width: 40, height: 40,
                                                                                    using: NCDatabaseManager.sharedInstance().activeAccount()),
                              placeholderImage: image, success: nil, failure: nil)
        }
        return cell
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
            if let pollId = Int(message.poll().parameterId) {
                presentPoll(pollId: pollId)
            }
        default:
            return
        }
    }
}
