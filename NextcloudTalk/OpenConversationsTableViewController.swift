//
// Copyright (c) 2023 Ivan Sein <ivan@nextcloud.com>
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

class OpenConversationsTableViewController: UITableViewController, UISearchResultsUpdating {

    var openConversations: [NCRoom] = []
    var filteredConversations: [NCRoom] = []
    let searchController: UISearchController = UISearchController(searchResultsController: nil)

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: NCAppBranding.themeTextColor()]
        self.navigationController?.navigationBar.tintColor = NCAppBranding.themeTextColor()
        self.navigationController?.navigationBar.barTintColor = NCAppBranding.themeColor()
        self.navigationController?.navigationBar.isTranslucent = false
        self.navigationItem.title = NSLocalizedString("Open conversations", comment: "")

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.titleTextAttributes = [.foregroundColor: NCAppBranding.themeTextColor()]
        appearance.backgroundColor = NCAppBranding.themeColor()
        self.navigationItem.standardAppearance = appearance
        self.navigationItem.compactAppearance = appearance
        self.navigationItem.scrollEdgeAppearance = appearance

        self.tableView.separatorInset = UIEdgeInsets(top: 0, left: 64, bottom: 0, right: 0)
        self.tableView.register(UINib(nibName: kContactsTableCellNibName, bundle: nil), forCellReuseIdentifier: kContactCellIdentifier)

        searchController.searchBar.placeholder = NSLocalizedString("Search", comment: "")
        searchController.searchResultsUpdater = self
        searchController.searchBar.sizeToFit()
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.tintColor = NCAppBranding.themeTextColor()

        if let searchTextField = searchController.searchBar.value(forKey: "searchField") as? UITextField {
            searchTextField.tintColor = NCAppBranding.themeTextColor()
            searchTextField.textColor = NCAppBranding.themeTextColor()

            DispatchQueue.main.async {
                // Search bar placeholder
                searchTextField.attributedPlaceholder = NSAttributedString(string: NSLocalizedString("Search", comment: ""),
                                                                           attributes: [NSAttributedString.Key.foregroundColor: NCAppBranding.themeTextColor().withAlphaComponent(0.5)])
                // Search bar search icon
                if let searchImageView = searchTextField.leftView as? UIImageView {
                    searchImageView.image = searchImageView.image?.withRenderingMode(.alwaysTemplate)
                    searchImageView.tintColor = NCAppBranding.themeTextColor().withAlphaComponent(0.5)
                }
                // Search bar search clear button
                if let clearButton = searchTextField.value(forKey: "_clearButton") as? UIButton {
                    let clearButtonImage = clearButton.imageView?.image?.withRenderingMode(.alwaysTemplate)
                    clearButton.setImage(clearButtonImage, for: .normal)
                    clearButton.setImage(clearButtonImage, for: .highlighted)
                    clearButton.tintColor = NCAppBranding.themeTextColor()
                }
            }
        }

        self.navigationItem.searchController = searchController
        self.navigationItem.searchController?.searchBar.searchTextField.backgroundColor = NCUtils.searchbarBGColor(for: NCAppBranding.themeColor())
        // Fix uisearchcontroller animation
        self.extendedLayoutIncludesOpaqueBars = true
    }

    override func viewWillAppear(_ animated: Bool) {
        searchForListableRooms()
        self.navigationItem.hidesSearchBarWhenScrolling = false
    }

    // MARK: - Search open conversations

    func searchForListableRooms() {
        NCAPIController.sharedInstance().getListableRooms(for: NCDatabaseManager.sharedInstance().activeAccount(), withSearchTerm: "") { listableRooms, _, _ in
            if let listableRooms = listableRooms as? [NCRoom] {
                self.openConversations = listableRooms
            }
            self.tableView.reloadData()
        }
    }

    func filterConversationsWithSearchTerm(searchTerm: String) {
        filteredConversations = openConversations.filter({ (room: NCRoom) -> Bool in
            return room.displayName!.range(of: searchTerm, options: NSString.CompareOptions.caseInsensitive) != nil
        })
    }

    func updateSearchResults(for searchController: UISearchController) {
        if let searchTerm = searchController.searchBar.text {
            filterConversationsWithSearchTerm(searchTerm: searchTerm)
            tableView.reloadData()
        }
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if searchController.isActive {
            return filteredConversations.count
        }
        return openConversations.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: kContactCellIdentifier) as? ContactsTableViewCell ??
        ContactsTableViewCell(style: .default, reuseIdentifier: kContactCellIdentifier)

        var openConversation = openConversations[indexPath.row]
        if searchController.isActive {
            openConversation = filteredConversations[indexPath.row]
        }

        cell.labelTitle.text = openConversation.displayName
        // Set group avatar as default avatar
        cell.contactImage.setGroupAvatar(with: self.traitCollection.userInterfaceStyle)
        // Try to get room avatar even though at the moment (Talk 17) it is not exposed
        cell.contactImage.setAvatar(for: openConversation, with: self.traitCollection.userInterfaceStyle)

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        var openConversation = openConversations[indexPath.row]
        if searchController.isActive {
            openConversation = filteredConversations[indexPath.row]
        }

        NCUserInterfaceController.sharedInstance().presentConversationsList()
        NCRoomsManager.sharedInstance().startChat(in: openConversation)
    }

}
