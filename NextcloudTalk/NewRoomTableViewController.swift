//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

enum NewRoomOption: Int {
    case createNewRoom = 0
    case joinOpenRoom
}

@objcMembers class NewRoomTableViewController: UITableViewController,
                                               UINavigationControllerDelegate,
                                               UISearchResultsUpdating {

    var account: TalkAccount

    var indexes: [String] = [""]
    var contacts: [String: [NCUser]] = [:]

    var searchController: UISearchController
    let resultTableViewController = ContactsSearchResultTableViewController(style: .insetGrouped)

    var searchTimer: Timer?
    var searchRequest: URLSessionTask?

    init(account: TalkAccount) {
        self.account = account
        self.searchController = UISearchController(searchResultsController: resultTableViewController)
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.navigationItem.hidesSearchBarWhenScrolling = false
        self.getPossibleContacts()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.searchController = searchController
        
        NCAppBranding.styleViewController(self)

        self.navigationItem.title = NSLocalizedString("New conversation", comment: "")

        self.resultTableViewController.tableView.delegate = self
        self.searchController.searchResultsUpdater = self

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(self.cancelButtonPressed))

        if #unavailable(iOS 26.0) {
            self.navigationItem.leftBarButtonItem?.tintColor = NCAppBranding.themeTextColor()
        }

        self.tableView.register(UINib(nibName: kContactsTableCellNibName, bundle: nil), forCellReuseIdentifier: kContactCellIdentifier)
    }

    func cancelButtonPressed() {
        self.dismiss(animated: true, completion: nil)
    }

    // MARK: - New room options

    func getNewRoomOptions() -> [NewRoomOption] {
        var options = [NewRoomOption]()

        // New group room
        if NCSettingsController.sharedInstance().canCreateGroupAndPublicRooms() {
            options.append(.createNewRoom)
        }

        // List open rooms
        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityListableRooms, forAccountId: self.account.accountId) {
            options.append(.joinOpenRoom)
        }

        return options
    }

    // MARK: - Contacts

    func getPossibleContacts() {
        NCAPIController.sharedInstance().getContactsFor(account, forRoom: "new", groupRoom: false, withSearchParam: "") { indexes, _, contactList, error in
            if error == nil, let indexes = indexes as? [String], let contactList = contactList as? [NCUser] {
                let storedContacts = NCContact.contacts(forAccountId: self.account.accountId, contains: nil)
                let combinedContactList = NCUser.combineUsersArray(storedContacts, withUsersArray: contactList)
                if let combinedContacts = NCUser.indexedUsers(fromUsersArray: combinedContactList) {
                    let combinedIndexes = Array(combinedContacts.keys).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                    self.indexes.append(contentsOf: combinedIndexes)
                    self.contacts = combinedContacts
                    self.tableView.reloadData()
                }
            }
        }
    }

    // MARK: - Search

    func updateSearchResults(for searchController: UISearchController) {
        self.searchTimer?.invalidate()
        self.resultTableViewController.showSearchingUI()
        DispatchQueue.main.async {
            self.searchTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(self.searchForContacts), userInfo: nil, repeats: false)
        }
    }

    func searchForContacts() {
        if let searchTerm = self.searchController.searchBar.text, !searchTerm.isEmpty {
            self.searchForContactsWithSearchParameter(searchTerm)
        }
    }

    func searchForContactsWithSearchParameter(_ searchParameter: String) {
        searchRequest?.cancel()
        searchRequest = NCAPIController.sharedInstance().getContactsFor(account, forRoom: "new", groupRoom: false, withSearchParam: searchParameter) { indexes, contacts, contactList, error in
            if error == nil, let contactList = contactList as? [NCUser] {
                let storedContacts = NCContact.contacts(forAccountId: self.account.accountId, contains: searchParameter)
                let combinedContactList = NCUser.combineUsersArray(storedContacts, withUsersArray: contactList)
                if let combinedContacts = NCUser.indexedUsers(fromUsersArray: combinedContactList) {
                    let combinedIndexes = Array(combinedContacts.keys).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                    self.resultTableViewController.setSearchResultContacts(combinedContacts, indexes: combinedIndexes)
                }
            }
        }
    }

    // MARK: - TableView

    override func numberOfSections(in tableView: UITableView) -> Int {
        return indexes.count
    }

    override func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        return indexes
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return indexes[section]
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return getNewRoomOptions().count
        } else {
            let index = indexes[section]
            return contacts[index]?.count ?? 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        if indexPath.section == 0 {
            let options = getNewRoomOptions()
            let option = options[indexPath.row]
            var newRoomOptionCell = UITableViewCell()
            switch option {
            case .createNewRoom:
                newRoomOptionCell = tableView.dequeueReusableCell(withIdentifier: "NewGroupRoomCellIdentifier") ?? UITableViewCell(style: .default, reuseIdentifier: "NewGroupRoomCellIdentifier")
                newRoomOptionCell.textLabel?.text = NSLocalizedString("Create a new conversation", comment: "")
                newRoomOptionCell.imageView?.image = UIImage(systemName: "bubble")
            case .joinOpenRoom:
                newRoomOptionCell = tableView.dequeueReusableCell(withIdentifier: "ListOpenRoomsCellIdentifier") ?? UITableViewCell(style: .default, reuseIdentifier: "ListOpenRoomsCellIdentifier")
                newRoomOptionCell.textLabel?.text = NSLocalizedString("Join open conversations", comment: "")
                newRoomOptionCell.imageView?.image = UIImage(systemName: "list.bullet")
            }

            newRoomOptionCell.imageView?.tintColor = .secondaryLabel
            newRoomOptionCell.imageView?.contentMode = .scaleAspectFit
            newRoomOptionCell.textLabel?.numberOfLines = 0

            return newRoomOptionCell

        } else {
            let index = indexes[indexPath.section]
            let contactsForIndex = contacts[index]
            guard let contact = contactsForIndex?[indexPath.row] else {
                return UITableViewCell()
            }

            let contactCell = tableView.dequeueReusableCell(withIdentifier: kContactCellIdentifier) as? ContactsTableViewCell ??
            ContactsTableViewCell(style: .default, reuseIdentifier: kContactCellIdentifier)

            contactCell.labelTitle.text = contact.name

            let contactType = contact.source as String
            let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
            contactCell.contactImage.setActorAvatar(forId: contact.userId, withType: contactType, withDisplayName: contact.name, withRoomToken: nil, using: account)

            return contactCell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if searchController.isActive && !resultTableViewController.contacts.isEmpty {
            let index = resultTableViewController.indexes[indexPath.section]
            let contactsForIndex = resultTableViewController.contacts[index]
            guard let contact = contactsForIndex?[indexPath.row] else { return }

            self.createRoomWithContact(contact)
        } else if indexPath.section == 0 {
            let options = getNewRoomOptions()
            let option = options[indexPath.row]

            if option == .createNewRoom {
                self.presentCreateRoomViewController()
            } else if option == .joinOpenRoom {
                self.presentJoinOpenRoomsViewController()
            }

        } else {
            let index = indexes[indexPath.section]
            let contactsForIndex = contacts[index]
            guard let contact = contactsForIndex?[indexPath.row] else { return }

            self.createRoomWithContact(contact)
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }

    // MARK: - Actions

    func presentCreateRoomViewController() {
        let viewController = RoomCreationTableViewController(account: account)
        let navController = NCNavigationController(rootViewController: viewController)
        self.present(navController, animated: true)
    }

    func presentJoinOpenRoomsViewController() {
        let viewController = OpenConversationsTableViewController()
        let navController = NCNavigationController(rootViewController: viewController)
        self.present(navController, animated: true)
    }

    func createRoomWithContact(_ contact: NCUser) {
        NCAPIController.sharedInstance().createRoom(forAccount: account, withInvite: contact.userId, ofType: .oneToOne, andName: nil) { room, error in
            if let token = room?.token, error == nil {
                self.navigationController?.dismiss(animated: true) {
                    NotificationCenter.default.post(name: NSNotification.Name.NCSelectedUserForChat, object: self, userInfo: ["token": token])
                }
            }
        }
    }
}
