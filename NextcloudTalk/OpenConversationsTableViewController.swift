//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

class OpenConversationsTableViewController: UITableViewController, UISearchResultsUpdating {

    var openConversations: [NCRoom] = []
    var filteredConversations: [NCRoom] = []
    var didTriggerInitialSearch: Bool = false
    let tableBackgroundView: PlaceholderView = PlaceholderView()
    let searchController: UISearchController = UISearchController(searchResultsController: nil)

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.searchController = searchController
        NCAppBranding.styleViewController(self)

        self.navigationItem.title = NSLocalizedString("Open conversations", comment: "")

        self.tableView.separatorInset = UIEdgeInsets(top: 0, left: 64, bottom: 0, right: 0)
        self.tableView.register(UINib(nibName: kContactsTableCellNibName, bundle: nil), forCellReuseIdentifier: kContactCellIdentifier)

        tableBackgroundView.setImage(UIImage(named: "conversations-placeholder"))
        tableBackgroundView.placeholderTextView.text = NSLocalizedString("No results found", comment: "")
        tableBackgroundView.placeholderView.isHidden = true
        tableBackgroundView.loadingView.startAnimating()
        self.tableView.backgroundView = tableBackgroundView

        searchController.searchBar.placeholder = NSLocalizedString("Search", comment: "")
        searchController.searchResultsUpdater = self
        searchController.searchBar.sizeToFit()
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.obscuresBackgroundDuringPresentation = false

        if navigationController?.viewControllers.first == self {
            let barButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: nil)
            barButtonItem.primaryAction = UIAction(title: "", handler: { [unowned self] _ in
                self.dismiss(animated: true)
            })
            self.navigationItem.leftBarButtonItems = [barButtonItem]
        }

        // Fix uisearchcontroller animation
        self.extendedLayoutIncludesOpaqueBars = true
    }

    override func viewWillAppear(_ animated: Bool) {
        self.navigationItem.hidesSearchBarWhenScrolling = false

        if !didTriggerInitialSearch {
            searchForListableRooms()
            didTriggerInitialSearch = true
        }
    }

    // MARK: - Search open conversations

    func searchForListableRooms() {
        NCAPIController.sharedInstance().getListableRooms(forAccount: .active, withSerachTerm: "") { listableRooms, _ in

            self.tableBackgroundView.loadingView.stopAnimating()
            self.tableBackgroundView.loadingView.isHidden = true

            if let listableRooms {
                self.openConversations = listableRooms
                self.tableBackgroundView.placeholderView.isHidden = !listableRooms.isEmpty
            } else {
                self.tableBackgroundView.placeholderView.isHidden = false
            }

            self.tableView.reloadData()
        }
    }

    func filterConversationsWithSearchTerm(searchTerm: String) {
        if searchTerm.isEmpty {
            filteredConversations = openConversations
        } else {
            filteredConversations = openConversations.filter({ (room: NCRoom) -> Bool in
                return room.displayName!.range(of: searchTerm, options: NSString.CompareOptions.caseInsensitive) != nil
            })
        }

        self.tableBackgroundView.placeholderView.isHidden = !filteredConversations.isEmpty
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
        cell.contactImage.setGroupAvatar()
        // Try to get room avatar even though at the moment (Talk 17) it is not exposed
        cell.contactImage.setAvatar(for: openConversation)
        // Set description
        cell.setUserStatusMessage(openConversation.roomDescription, withIcon: nil)

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
