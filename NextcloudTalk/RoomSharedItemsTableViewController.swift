/**
 * @copyright Copyright (c) 2022 Ivan Sein <ivan@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
 *
 * @license GNU GPL version 3 or any later version
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

import UIKit
import QuickLook

@objcMembers class RoomSharedItemsTableViewController: UITableViewController, NCChatFileControllerDelegate, QLPreviewControllerDelegate, QLPreviewControllerDataSource {
    let roomToken: String
    let account: TalkAccount = NCDatabaseManager.sharedInstance().activeAccount()
    var sharedItemsOverview: [String: [NCChatMessage]] = [:]
    var currentItems: [NCChatMessage] = []
    var currentItemType: String = "all"
    var sharedItemsBackgroundView: PlaceholderView = PlaceholderView()
    var previewControllerFilePath: String = ""
    var isPreviewControllerShown: Bool = false

    init(roomToken: String) {
        self.roomToken = roomToken
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

        if #available(iOS 13.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.titleTextAttributes = [.foregroundColor: NCAppBranding.themeTextColor()]
            appearance.backgroundColor = NCAppBranding.themeColor()
            self.navigationItem.standardAppearance = appearance
            self.navigationItem.compactAppearance = appearance
            self.navigationItem.scrollEdgeAppearance = appearance
        }

        self.tableView.register(UINib(nibName: kDirectoryTableCellNibName, bundle: nil), forCellReuseIdentifier: kDirectoryCellIdentifier)

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
                action.setValue(UIImage(named: "checkmark")?.withRenderingMode(_:.alwaysOriginal), forKey: "image")
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
            .getSharedItems(ofType: itemType, fromLastMessageId: -1, withLimit: -1,
                            inRoom: roomToken, for: account) { items, _, error, _ in
                if error == nil {
                    self.currentItems = items as? [NCChatMessage] ?? []
                    self.tableView.reloadData()
                }
                self.hideFetchingItemsPlaceholderView()
            }
    }

    func getItemsOverview() {
        showFetchingItemsPlaceholderView()
        NCAPIController.sharedInstance()
            .getSharedItemsOverview(inRoom: roomToken, withLimit: -1, for: account) { itemsOverview, error, _ in
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

    func nameForItemType(itemType: String) -> String {
        switch itemType {
        case kSharedItemTypeAudio:
            return NSLocalizedString("Audios", comment: "")
        case kSharedItemTypeDeckcard:
            return NSLocalizedString("Deckcards", comment: "")
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
        default:
            return NSLocalizedString("Shared items", comment: "")
        }
    }

    func imageNameForMessage(message: NCChatMessage) -> String {
        var imageName = "file"
        if message.file() != nil {
            imageName = NCUtils.previewImage(forFileMIMEType: message.file().mimetype)
        }
        return imageName
    }

    // MARK: - File downloader

    func downloadFileForCell(cell: DirectoryTableViewCell, message: NCChatMessage) {
        cell.fileParameter = message.file()
        let downloader = NCChatFileController()
        downloader.delegate = self
        downloader.downloadFile(fromMessage: message.file())
    }

    func fileControllerDidLoadFile(_ fileController: NCChatFileController, with fileStatus: NCChatFileStatus) {
        DispatchQueue.main.async {
            if self.isPreviewControllerShown {return}
            let previewController = QLPreviewController()
            previewController.dataSource = self
            previewController.delegate = self
            self.previewControllerFilePath = fileStatus.fileLocalPath
            self.isPreviewControllerShown = true
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

    // MARK: - Locations

    func presentLocation(location: GeoLocationRichObject) {
        let mapViewController = MapViewController(geoLocationRichObject: location)
        let navigationViewController = NCNavigationController(rootViewController: mapViewController)
        self.present(navigationViewController, animated: true, completion: nil)
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
        cell.fileInfoLabel?.text = NCUtils.relativeTime(from: Date(timeIntervalSince1970: Double(message.timestamp)))

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
        case kSharedItemTypeMedia, kSharedItemTypeFile, kSharedItemTypeVoice:
            downloadFileForCell(cell: cell, message: message)
        case kSharedItemTypeLocation:
            presentLocation(location: GeoLocationRichObject(from: message.geoLocation()))
        default:
            return
        }
    }
}
