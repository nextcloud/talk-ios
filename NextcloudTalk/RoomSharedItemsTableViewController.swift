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

@objcMembers class RoomSharedItemsTableViewController: UITableViewController {

    var sharedItems: [String: [NCChatMessage]] = [:]
    var filterType: String = "all"

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

        self.navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "sorting"), style: .plain, target: self, action: #selector(self.filterButtonPressed))
        self.navigationItem.rightBarButtonItem?.tintColor = NCAppBranding.themeTextColor()
    }

    func filterButtonPressed() {
        // TODO: Implement items filter
    }

    func itemsForFilterType(filterType: String) -> [NCChatMessage] {
        if filterType == "all" {
            var allItems: [NCChatMessage] = []
            sharedItems.values.forEach { items in
                allItems.append(contentsOf: items)
            }
            return allItems
        }
        return sharedItems[filterType] ?? []
    }

    func addSharedItems(sharedItems: [String: [NCChatMessage]]) {
        self.sharedItems = sharedItems
        self.tableView.reloadData()
    }

    func imageNameForMessage(message: NCChatMessage) -> String {
        var imageName = "file"
        if message.file() != nil {
            imageName = NCUtils.previewImage(forFileMIMEType: message.file().mimetype)
        }
        return imageName
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let itemsForType = itemsForFilterType(filterType: filterType)
        return itemsForType.count
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return kDirectoryTableCellHeight
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: kDirectoryCellIdentifier) as? DirectoryTableViewCell ??
        DirectoryTableViewCell(style: .default, reuseIdentifier: kShareCellIdentifier)

        let itemsForType = itemsForFilterType(filterType: filterType)
        let message = itemsForType[indexPath.row]

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
}
